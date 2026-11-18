@echo off
chcp 65001 >nul
title STX Control - Organizar pendrive
powershell -NoProfile -ExecutionPolicy Bypass -Command "$f='%~f0'; $a='%~1'; $m='#__'+'PS__#'; iex ((Get-Content -LiteralPath $f -Encoding UTF8 -Raw) -split [regex]::Escape($m),2)[1]"
exit /b
#__PS__#
$ErrorActionPreference = 'Continue'
$audio = '\.(mp3|wma|wav|flac|aac|m4a)$'
$script:drive = $null

# formato novo: ESTILO#NOME  (o estilo vai no COMECO do nome; o app esconde o "ESTILO#" na tela)
# O numero da subpasta e mantido (ex.: SERTANEJO#01 Felipe e Rodrigo) para a ordem ficar igual ao pendrive.
# Hashtag do nome (ex.: "#NoSentimento") NAO e mexida: so conta como marcacao antiga ("NOME #ESTILO")
# quando o texto depois do # e um estilo conhecido (nome de uma pasta principal).
$script:estilos = @()
function Norm([string]$x) { ($x.Normalize([Text.NormalizationForm]::FormD) -replace '\p{Mn}', '').Trim().ToUpper() }
function EhEstilo([string]$x) { $k = Norm $x; foreach ($e in $script:estilos) { if ((Norm $e) -eq $k) { return $true } }; return $false }
$rxNovo = '^\s*([^#\d][^#]*?\S)#\s*(\S.*)$'
function Limpa([string]$n) {
  if ($n -match '^(.*\S)\s+#\s*([^#]+?)\s*$' -and (EhEstilo $matches[2])) { $n = $matches[1] }   # marcacao antiga no fim
  if ($n -match $rxNovo) { $n = $matches[2] }                                                     # estilo na frente
  $n.Trim()
}
function TagDe([string]$n) {
  if ($n -match $rxNovo) { return $matches[1].Trim() }
  if ($n -match '^(.*\S)\s+#\s*([^#]+?)\s*$' -and (EhEstilo $matches[2])) { return $matches[2].Trim() }
  return $null
}

# pastas com musica (sao as que o processador mostra), da mais funda para a mais rasa
function TemMusica($p) { @(Get-ChildItem -LiteralPath $p.FullName -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $audio }).Count -gt 0 }
function PastasComMusica([string]$dir) {
  $self = Get-Item -LiteralPath $dir
  $lista = @(Get-ChildItem -LiteralPath $dir -Directory -Recurse -ErrorAction SilentlyContinue | Where-Object { TemMusica $_ })
  if ($self.Parent -and (TemMusica $self)) { $lista += $self }   # a propria pasta tambem, se tiver musica (nunca a raiz do pendrive)
  $lista | Sort-Object { $_.FullName.Length } -Descending
}

function Renomeia($pasta, [string]$novo) {
  if ($novo -ceq $pasta.Name) { return $false }
  try { Rename-Item -LiteralPath $pasta.FullName -NewName $novo -ErrorAction Stop; return $true }
  catch { Write-Host "   Nao consegui renomear: $($pasta.Name)  ($($_.Exception.Message))" -ForegroundColor Red; return $false }
}

# subpastas com musica de uma arvore (sem contar a propria arvore)
function Subpastas([string]$dir) { $self = (Get-Item -LiteralPath $dir).FullName; @(PastasComMusica $dir | Where-Object { $_.FullName -ne $self }) }
function Soltas([string]$dir) { @(Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $audio }) }

# marca as SUBPASTAS da arvore (ESTILO#NOME) e as MUSICAS SOLTAS dela (ESTILO#musica.mp3)
# a propria pasta da arvore nao ganha copia do nome; arvore sem subpastas nao e mexida
function Marca([string]$dir, [string]$grupo) {
  if (-not (EhEstilo $grupo)) { $script:estilos += $grupo }
  $lista = @(Subpastas $dir)
  if (-not $lista.Count) { Write-Host "   (sem subpastas - nao precisa marcar)" -ForegroundColor DarkGray; return }
  $n = 0
  foreach ($s in $lista) { if (Renomeia $s "$grupo#$(Limpa $s.Name)") { $n++ } }
  $m = 0
  foreach ($f in @(Soltas $dir)) { if (Renomeia $f "$grupo#$(Limpa $f.Name)") { $m++ } }
  Write-Host "   OK: $n pasta(s) e $m musica(s) solta(s) marcada(s) com $grupo#" -ForegroundColor Green
}

# tira a marcacao (todas, ou so de um grupo) - pastas e musicas
function Desmarca([string]$dir, [string]$soGrupo) {
  $n = 0
  $itens = @(PastasComMusica $dir)
  $itens += @(Soltas $dir)
  foreach ($p in @(PastasComMusica $dir)) { $itens += @(Soltas $p.FullName) }
  foreach ($s in ($itens | Sort-Object FullName -Unique | Sort-Object { $_.FullName.Length } -Descending)) {
    $t = TagDe $s.Name
    if (-not $t) { continue }
    if ($soGrupo -and ((Norm $t) -ne (Norm $soGrupo))) { continue }
    if (Renomeia $s (Limpa $s.Name)) { $n++ }
  }
  Write-Host "   OK: marcacao tirada de $n item(ns)." -ForegroundColor Green
}

function Pendrive {
  if ($script:drive -and (Test-Path -LiteralPath $script:drive)) {
    $r = Read-Host "  Usar o pendrive $($script:drive)? (Enter = sim, ou digite outra letra)"
    if (-not $r) { return $script:drive }
  } else { $r = Read-Host "  Letra do pendrive (ex.: E)" }
  $l = $r.Trim().TrimEnd(':', '\')
  $d = "$($l):\"
  if (-not $l -or -not (Test-Path -LiteralPath $d)) { Write-Host "  Nao achei o pendrive $d" -ForegroundColor Red; return $null }
  $script:drive = $d
  $script:estilos = @(Principais $d | ForEach-Object { NomeAuto $_.Name @() })
  return $d
}

function Principais([string]$d) {
  Get-ChildItem -LiteralPath $d -Directory | Where-Object { $_.Name -notmatch '^(System Volume Information|\$RECYCLE\.BIN)$' } | Sort-Object Name
}

# nome automatico: pula o numero da frente, tira ano, @perfil, "E MELHORES" e a assinatura repetida (ex.: RafinhaCds)
function NomeAuto([string]$n, [string[]]$assin) {
  if ($n -match '^\s*([^#\d][^#]*?\S)#\s*\S') { return $matches[1].Trim().ToUpper() }   # ja marcada: "PISEIRO#03 PISEIRO" -> PISEIRO
  $t = $n -replace '^\s*\d{1,3}\s*[-._)]?\s*', ''
  foreach ($x in $assin) { if ($x) { $t = $t -replace ('\s+' + [regex]::Escape($x) + '\s*$'), '' } }
  $t = $t -replace '\b(19|20)\d{2}\b', ' '
  $t = $t -replace '@\S+', ' '   # tira o @ do gravador (ex.: @_ismaeldivulgacoes)
  $t = ($t -replace '\s+', ' ').Trim()
  $t = ($t -replace '\s*\b(E\s+)?(AS\s+)?MELHORES$', '').Trim()
  if (-not $t) { $t = ($n -replace '^\s*\d{1,3}\s*[-._)]?\s*', '').Trim() }
  return $t.ToUpper()
}

# tira o numero da frente das pastas da RAIZ do pendrive
#   "SERESTA#17 SERESTA" -> "SERESTA#SERESTA"      "02 FORRO NOVO" -> "FORRO NOVO"
$rxNum = '^\s*\d{1,3}(?!\d)\s*[-._)]?\s*'
function SemNumero([string]$n) {
  if ($n -match '^\s*([^#\d][^#]*?\S)#\s*(\S.*)$') {
    $resto = ($matches[2] -replace $rxNum, '').Trim()
    if ($resto) { return "$($matches[1].Trim())#$resto" } else { return $n }
  }
  $t = ($n -replace $rxNum, '').Trim()
  if ($t) { return $t } else { return $n }
}
function EstiloDaArvore($t) {
  foreach ($x in @(Subpastas $t.FullName)) { $g = TagDe $x.Name; if ($g) { return $g } }
  $g = TagDe $t.Name; if ($g) { return $g }
  return (NomeAuto $t.Name @())
}
# nome que a pasta da raiz deve ter: "SERESTA#17 SERESTA" -> "SERESTA"; "02 FORRO NOVO" -> "FORRO NOVO"
function NomeRaiz($t) {
  if (@(Subpastas $t.FullName).Count) { return (EstiloDaArvore $t) }   # igual ao estilo das subpastas: o app junta tudo
  return (SemNumero (Limpa $t.Name))
}
function TiraNumeroRaiz([string]$d) {
  $n = 0
  foreach ($t in @(Principais $d)) {
    $novo = NomeRaiz $t
    if (-not $novo -or $novo -ceq $t.Name) { continue }
    if ((Test-Path -LiteralPath (Join-Path $d $novo)) -and ($novo -ne $t.Name)) { Write-Host "   Ja existe uma pasta '$novo' - nao mexi em '$($t.Name)'" -ForegroundColor Yellow; continue }
    if (Renomeia $t $novo) { $n++ }
  }
  Write-Host "   OK: $n pasta(s) da raiz arrumada(s)." -ForegroundColor Green
}

# nome livre na raiz: "NOME (2)", "NOME (3)"...
function Livre([string]$d, [string]$nome, [bool]$arquivo) {
  $alvo = Join-Path $d $nome; if (-not (Test-Path -LiteralPath $alvo)) { return $alvo }
  $base = $nome; $ext = ''
  if ($arquivo) { $base = [IO.Path]::GetFileNameWithoutExtension($nome); $ext = [IO.Path]::GetExtension($nome) }
  for ($i = 2; $i -lt 1000; $i++) { $alvo = Join-Path $d "$base ($i)$ext"; if (-not (Test-Path -LiteralPath $alvo)) { return $alvo } }
  return $null
}
# JOGA TUDO NA RAIZ: subpastas e musicas soltas de cada arvore vao para a raiz, ja marcadas com ESTILO#
function JogaNaRaiz([string]$d, $arvores) {
  $np = 0; $nm = 0
  foreach ($a in $arvores) {
    $est = $a.Estilo
    Write-Host "  $($a.Pasta.Name)  ->  $est#"
    foreach ($s in @(Subpastas $a.Pasta.FullName)) {
      $nome = $s.Name; if (-not (TagDe $nome)) { $nome = "$est#$nome" }
      $alvo = Livre $d $nome $false
      try { Move-Item -LiteralPath $s.FullName -Destination $alvo -ErrorAction Stop; $np++ } catch { Write-Host "   Nao consegui mover a pasta $($s.Name): $($_.Exception.Message)" -ForegroundColor Red }
    }
    foreach ($f in @(Soltas $a.Pasta.FullName)) {
      $nome = $f.Name; if ($nome -notmatch $rxNovo) { $nome = "$est#$nome" }
      $alvo = Livre $d $nome $true
      try { Move-Item -LiteralPath $f.FullName -Destination $alvo -ErrorAction Stop; $nm++ } catch { Write-Host "   Nao consegui mover $($f.Name): $($_.Exception.Message)" -ForegroundColor Red }
    }
    # a pasta da arvore ficou vazia? entao some com ela
    if (-not @(Get-ChildItem -LiteralPath $a.Pasta.FullName -Recurse -File -Force -ErrorAction SilentlyContinue).Count) {
      try { Remove-Item -LiteralPath $a.Pasta.FullName -Recurse -Force -ErrorAction Stop } catch { }
    } else { Write-Host "   Sobrou arquivo que nao e musica em '$($a.Pasta.Name)' - a pasta ficou." -ForegroundColor Yellow }
  }
  Write-Host ""
  Write-Host "   OK: $np pasta(s) e $nm musica(s) foram para a raiz do pendrive." -ForegroundColor Green
}

function Volta { Write-Host ""; Read-Host "  Enter para voltar ao inicio" | Out-Null }

function Menu {
  Clear-Host
  Write-Host ""
  Write-Host "  ==================================================" -ForegroundColor Yellow
  Write-Host "         STX CONTROL - ORGANIZAR PENDRIVE" -ForegroundColor Yellow
  Write-Host "  ==================================================" -ForegroundColor Yellow
  Write-Host "  Coloca o ESTILO no comeco do nome das subpastas, ex.:"
  Write-Host "     FORRO NOVO#REY VAQUEIRO - CD DE NOVEMBRO" -ForegroundColor Cyan
  Write-Host "  O app junta todas as FORRO NOVO# num grupo FORRO NOVO e"
  Write-Host "  esconde o 'FORRO NOVO#' na tela. Musica solta vira FORRO NOVO#musica.mp3"
  Write-Host "  O numero das subpastas fica (a ordem nao muda). Hashtags nao sao mexidas."
  Write-Host ""
  Write-Host "  1 - AUTOMATICO: marca subpastas e musicas soltas com o ESTILO# e tira o numero da raiz"
  Write-Host "  2 - Pendrive inteiro, digitando o nome de cada pasta principal"
  Write-Host "  3 - Uma pasta so (voce digita o nome)"
  Write-Host "  4 - DESFAZER de UM estilo so (escolhe na lista)"
  Write-Host "  5 - Desfazer TUDO (tira todas as marcacoes)"
  Write-Host "  6 - Arrumar nome das pastas da raiz (tira numero e copia: SERESTA#17 SERESTA -> SERESTA)"
  Write-Host "  7 - JOGAR TUDO NA RAIZ do pendrive (pastas e musicas soltas, ja com o ESTILO# na frente)"
  Write-Host "  0 - Sair"
  Write-Host ""
  return (Read-Host "  Escolha")
}

# arrastou uma pasta em cima do arquivo: marca ela primeiro
if ($a -and (Test-Path -LiteralPath $a -PathType Container)) {
  $leaf = Split-Path $a -Leaf
  $sug = NomeAuto $leaf @()
  $g = Read-Host "  Nome do grupo para as pastas de '$leaf' (Enter = $sug)"
  if (-not $g) { $g = $sug }
  Marca $a $g.Trim()
  Volta
}

while ($true) {
  $op = Menu
  switch ($op) {
    '0' { return }
    '1' {
      $d = Pendrive; if (-not $d) { Volta; break }
      $tops = @(Principais $d)
      # assinatura repetida no fim do nome (aparece em pelo menos metade das pastas)
      $fim = $tops | ForEach-Object { ($_.Name.Trim() -split '\s+')[-1] } | Group-Object | Where-Object { $_.Count -ge 3 -and $_.Count -ge ($tops.Count / 2) } | ForEach-Object { $_.Name }
      $plano = foreach ($t in $tops) { [pscustomobject]@{ Pasta = $t; Grupo = (NomeAuto $t.Name @($fim)) } }
      Write-Host ""
      Write-Host "  Vai ficar assim:" -ForegroundColor Cyan
      foreach ($p in $plano) {
        if (@(Subpastas $p.Pasta.FullName).Count) { Write-Host ("   {0,-50} ->  subpastas e musicas soltas: {1}#..." -f $p.Pasta.Name, $p.Grupo) }
        else { Write-Host ("   {0,-50} ->  sem subpastas (so tira o numero)" -f $p.Pasta.Name) }
      }
      Write-Host ""
      $ok = Read-Host "  Aplicar em todas? (S = sim / N = nao)"
      if ($ok -match '^[sS]') { foreach ($p in $plano) { Write-Host "  $($p.Pasta.Name)"; Marca $p.Pasta.FullName $p.Grupo }; TiraNumeroRaiz $d }
      else { Write-Host "  Nada foi alterado." }
      Volta
    }
    '2' {
      $d = Pendrive; if (-not $d) { Volta; break }
      foreach ($t in @(Principais $d)) {
        $sug = NomeAuto $t.Name @()
        $g = Read-Host "  Grupo para '$($t.Name)'  (Enter = $sug, - = pular)"
        if ($g -eq '-') { continue }
        if (-not $g) { $g = $sug }
        Marca $t.FullName $g.Trim()
      }
      Volta
    }
    '3' {
      $p = (Read-Host "  Cole o caminho da pasta (ex.: E:\02 FORRO NOVO)").Trim('"', ' ')
      if (-not (Test-Path -LiteralPath $p -PathType Container)) { Write-Host "  Pasta nao encontrada." -ForegroundColor Red; Volta; break }
      $sug = NomeAuto (Split-Path $p -Leaf) @()
      $g = Read-Host "  Nome do grupo (Enter = $sug)"
      if (-not $g) { $g = $sug }
      Marca $p $g.Trim()
      Volta
    }
    '4' {
      $d = Pendrive; if (-not $d) { Volta; break }
      $todos = @(PastasComMusica $d) + @(Soltas $d); foreach ($p in @(PastasComMusica $d)) { $todos += @(Soltas $p.FullName) }
      $grupos = @($todos | ForEach-Object { TagDe $_.Name } | Where-Object { $_ } | Group-Object | Sort-Object Name)
      if (-not $grupos.Count) { Write-Host "  Nenhuma pasta marcada neste pendrive." -ForegroundColor DarkGray; Volta; break }
      Write-Host ""
      for ($i = 0; $i -lt $grupos.Count; $i++) { Write-Host ("   {0,3} - {1}  ({2} itens)" -f ($i + 1), $grupos[$i].Name, $grupos[$i].Count) }
      Write-Host ""
      $e = Read-Host "  Numero do estilo para DESFAZER (Enter = cancelar)"
      if ($e -match '^\d+$' -and [int]$e -ge 1 -and [int]$e -le $grupos.Count) { Desmarca $d $grupos[[int]$e - 1].Name }
      else { Write-Host "  Nada foi alterado." }
      Volta
    }
    '5' {
      $d = Pendrive; if (-not $d) { Volta; break }
      $ok = Read-Host "  Tirar TODAS as marcacoes de $d ? (S = sim / N = nao)"
      if ($ok -match '^[sS]') { Desmarca $d $null } else { Write-Host "  Nada foi alterado." }
      Volta
    }
    '6' {
      $d = Pendrive; if (-not $d) { Volta; break }
      $plano = @(Principais $d | Where-Object { (NomeRaiz $_) -cne $_.Name })
      if (-not $plano.Count) { Write-Host "  As pastas da raiz ja estao certas." -ForegroundColor DarkGray; Volta; break }
      Write-Host ""
      Write-Host "  Vai ficar assim:" -ForegroundColor Cyan
      foreach ($t in $plano) { Write-Host ("   {0,-50} ->  {1}" -f $t.Name, (NomeRaiz $t)) }
      Write-Host ""
      $ok = Read-Host "  Aplicar? (S = sim / N = nao)"
      if ($ok -match '^[sS]') { TiraNumeroRaiz $d } else { Write-Host "  Nada foi alterado." }
      Volta
    }
    '7' {
      $d = Pendrive; if (-not $d) { Volta; break }
      $arv = @(foreach ($t in @(Principais $d)) {
        $ns = @(Subpastas $t.FullName).Count; $nm = @(Soltas $t.FullName).Count
        if ($ns -or $nm) { [pscustomobject]@{ Pasta = $t; Estilo = (EstiloDaArvore $t); Subs = $ns; Mus = $nm } }
      })
      if (-not $arv.Count) { Write-Host "  Nada para mover." -ForegroundColor DarkGray; Volta; break }
      Write-Host ""
      Write-Host "  Vai para a RAIZ do pendrive:" -ForegroundColor Cyan
      foreach ($a in $arv) { Write-Host ("   {0,-40} ->  {1}#   ({2} pastas, {3} musicas soltas)" -f $a.Pasta.Name, $a.Estilo, $a.Subs, $a.Mus) }
      Write-Host ""
      Write-Host "  As pastas das arvores que ficarem vazias sao apagadas." -ForegroundColor Yellow
      $ok = Read-Host "  Jogar tudo na raiz? (S = sim / N = nao)"
      if ($ok -match '^[sS]') { JogaNaRaiz $d $arv } else { Write-Host "  Nada foi alterado." }
      Volta
    }
    default { }
  }
}
