#!/usr/bin/env bash
# =============================================================================
#  R36S PORT HUB - publicacao no GitHub com LINKS FIXOS
#
#  Os links nao mudam nunca. A cada publicacao o arquivo por tras deles e
#  substituido:
#
#    update   -> releases/latest/download/R36S-PORT-HUB-update.zip
#    completo -> releases/latest/download/R36S-PORT-HUB.zip
#    fonte    -> releases/latest/download/R36S-PORT-HUB-codigo-fonte.zip
#    temas    -> raw.githubusercontent.com/.../main/temas.json
#    metadados-> raw.githubusercontent.com/.../main/update.json
#
#  Uso:
#    ./publicar.sh links                  mostra os links fixos
#    ./publicar.sh setup   <pasta-final>  cria o repositorio e publica tudo
#    ./publicar.sh update  <zip|pasta>    publica uma atualizacao (1 por vez)
#    ./publicar.sh final   <zip|pasta>    publica o pacote completo + fonte
#    ./publicar.sh temas   <temas.json>   publica o catalogo de temas
#
#  Token: variavel GH_TOKEN/GITHUB_TOKEN ou arquivo ~/.config/r36s-port-hub/token
#  (nunca fica dentro do repositorio).
# =============================================================================
set -euo pipefail

SLUG="${R36S_SLUG:-liralflsti-wq/r36s-port-hub}"   # usuario/repositorio (troque com R36S_SLUG=...)
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST="$ROOT/dist"
TOKEN_FILE="${R36S_TOKEN_FILE:-$HOME/.config/r36s-port-hub/token}"
API="https://api.github.com"
UP_NAME="R36S-PORT-HUB-update.zip"
FULL_NAME="R36S-PORT-HUB.zip"
SRC_NAME="R36S-PORT-HUB-codigo-fonte.zip"

c()  { printf '\033[%sm%s\033[0m\n' "$1" "$2"; }
ok() { c '1;32' "  ok  $*"; }
info(){ c '1;36' "  ..  $*"; }
warn(){ c '1;33' "  !!  $*"; }
die(){ c '1;31' "  xx  $*" >&2; exit 1; }

need() { command -v "$1" >/dev/null 2>&1 || die "faltou o programa '$1'"; }
need curl; need git; need python3; need zip

# ---------------------------------------------------------------- token ------
load_token() {
  TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
  if [ -z "$TOKEN" ] && [ -f "$TOKEN_FILE" ]; then
    TOKEN="$(tr -d ' \t\r\n' < "$TOKEN_FILE")"
  fi
  [ -n "$TOKEN" ] || die "sem token. Crie $TOKEN_FILE (uma linha com o token) ou exporte GH_TOKEN=..."
  export GH_TOKEN="$TOKEN"
}

api() {  # api METODO CAMINHO [json]
  local method="$1" path="$2" data="${3:-}"
  if [ -n "$data" ]; then
    curl -sS -X "$method" \
      -H "Authorization: Bearer $TOKEN" \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      -H "Content-Type: application/json" \
      --data-binary "$data" "$API$path"
  else
    curl -sS -X "$method" \
      -H "Authorization: Bearer $TOKEN" \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" "$API$path"
  fi
}

jget() {  # jget '.a.b' <<< json
  python3 -c '
import sys, json
try: d = json.load(sys.stdin)
except Exception: print(""); sys.exit(0)
for k in sys.argv[1].strip(".").split("."):
    if not k: continue
    d = d[int(k)] if isinstance(d, list) else (d.get(k) if isinstance(d, dict) else None)
    if d is None: print(""); sys.exit(0)
print(d if not isinstance(d, (dict, list)) else json.dumps(d, ensure_ascii=False))
' "$1"
}

sha256() { python3 -c 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$1"; }
fsize()  { python3 -c 'import os,sys;print(os.path.getsize(sys.argv[1]))' "$1"; }

# ---------------------------------------------------------------- links ------
show_links() {
  echo
  c '1;35' "  LINKS FIXOS (nunca mudam)"
  echo   "  updates : https://github.com/$SLUG/releases/latest/download/$UP_NAME"
  echo   "  completo: https://github.com/$SLUG/releases/latest/download/$FULL_NAME"
  echo   "  fonte   : https://github.com/$SLUG/releases/latest/download/$SRC_NAME"
  echo   "  temas   : https://raw.githubusercontent.com/$SLUG/main/temas.json"
  echo   "  metadata: https://raw.githubusercontent.com/$SLUG/main/update.json"
  echo   "  pagina  : https://github.com/$SLUG"
  echo
}

# ------------------------------------------------------------ arquivos ------
pick_file() {  # pick_file <pasta|arquivo> <sufixo...>
  local p="$1"; shift
  [ -e "$p" ] || die "nao achei: $p"
  if [ -f "$p" ]; then echo "$p"; return; fi
  local f
  for pat in "$@"; do
    f="$(ls -1t "$p"/$pat 2>/dev/null | head -1 || true)"
    [ -n "$f" ] && { echo "$f"; return; }
  done
  die "nenhum arquivo ($*) em $p"
}

# monta o .zip completo a partir de uma pasta com "R36S PORT HUB.sh" + r36sporthub/
build_full_zip() {  # build_full_zip <pasta> <saida>
  local dir="$1" out="$2"
  [ -f "$dir/R36S PORT HUB.sh" ] || [ -d "$dir/port" ] || die "pasta sem o launcher nem port/: $dir"
  mkdir -p "$(dirname "$out")"; rm -f "$out"
  if [ -f "$dir/R36S PORT HUB.sh" ]; then
    ( cd "$dir" && zip -qr "$out" "R36S PORT HUB.sh" r36sporthub -x "*/tmp/*" "*/logs/*" )
  else
    ( cd "$dir/port" && zip -qr "$out" "R36S PORT HUB.sh" r36sporthub -x "*/tmp/*" "*/logs/*" )
  fi
  ok "pacote montado: $(basename "$out") ($(du -h "$out" | cut -f1))"
}

manifest_from_zip() {  # imprime o update_manifest.json de dentro do zip
  local z="$1"
  python3 - "$z" <<'PY'
import sys, zipfile, json
z = zipfile.ZipFile(sys.argv[1])
for n in z.namelist():
    if n.rsplit("/", 1)[-1] == "update_manifest.json":
        print(z.read(n).decode("utf-8-sig")); break
PY
}

# ------------------------------------------------------------ release ------
release_info() {  # release_info <tag> -> id
  api GET "/repos/$SLUG/releases/tags/$1" | jget '.id'
}

drop_release() {  # apaga release e tag (para reaproveitar a mesma versao)
  local tag="$1" id
  id="$(release_info "$tag")"
  [ -n "$id" ] || return 0
  info "removendo release antiga $tag (id $id)"
  api DELETE "/repos/$SLUG/releases/$id" >/dev/null
  api DELETE "/repos/$SLUG/git/refs/tags/$tag" >/dev/null || true
}

ensure_release() {  # ensure_release <tag> <nome> <corpo-md> -> id
  local tag="$1" name="$2" body="$3" id payload
  id="$(release_info "$tag")"
  if [ -n "$id" ]; then echo "$id"; return; fi
  payload="$(python3 -c '
import json, sys
print(json.dumps({"tag_name": sys.argv[1], "name": sys.argv[2], "body": sys.argv[3],
                  "draft": False, "prerelease": False}))' "$tag" "$name" "$body")"
  api POST "/repos/$SLUG/releases" "$payload" | jget '.id'
}

upload_asset() {  # upload_asset <release_id> <arquivo> <nome-no-release>
  local rid="$1" file="$2" name="$3" resp code existing
  existing="$(api GET "/repos/$SLUG/releases/$rid/assets?per_page=100" \
    | python3 -c '
import sys, json
name = sys.argv[1]
for a in json.load(sys.stdin):
    if a.get("name") == name:
        print(a["id"]); break
' "$name")"
  if [ -n "$existing" ]; then
    info "substituindo anexo $name"
    api DELETE "/repos/$SLUG/releases/assets/$existing" >/dev/null
  fi
  info "enviando $name ($(du -h "$file" | cut -f1))"
  resp="$(curl -sS -X POST \
    -H "Authorization: Bearer $TOKEN" \
    -H "Accept: application/vnd.github+json" \
    -H "Content-Type: application/octet-stream" \
    --data-binary @"$file" \
    "https://uploads.github.com/repos/$SLUG/releases/$rid/assets?name=$name")"
  code="$(printf '%s' "$resp" | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
    print("ok" if d.get("state") in ("uploaded", "starter") or d.get("browser_download_url") else (d.get("message") or "erro"))
except Exception:
    print("erro")')"
  [ "$code" = "ok" ] || die "falha ao enviar $name: $code"
  ok "$name publicado"
}

# ------------------------------------------------------------ update.json --
write_update_json() {  # write_update_json <zip-update> <manifest-json>
  local z="$1" man="$2"
  python3 - "$z" "$man" "$SLUG" > "$ROOT/update.json" <<'PY'
import sys, json, hashlib, os
z, man, slug = sys.argv[1], sys.argv[2], sys.argv[3]
m = json.loads(man)
notes = [m.get("description", "")]
notes += ["* " + c for c in m.get("changes", [])]
notes += ["* (corrigido) " + c for c in m.get("fixes", [])]
h = hashlib.sha256(open(z, "rb").read()).hexdigest()
out = {
    "version": m.get("version", ""),
    "version_label": m.get("version_label", m.get("version", "")),
    "date": m.get("date", ""),
    "url": f"https://github.com/{slug}/releases/latest/download/R36S-PORT-HUB-update.zip",
    "size": os.path.getsize(z),
    "sha256": h,
    "min_version": m.get("min_version", ""),
    "notes": "\n".join(n for n in notes if n and n != "* "),
}
print(json.dumps(out, ensure_ascii=False, indent=2))
PY
  ok "update.json atualizado (versao $(jget '.version' < "$ROOT/update.json"))"
}

release_body() {  # markdown das notas
  python3 - "$1" <<'PY'
import sys, json
m = json.loads(sys.argv[1])
out = [m.get("description", "").strip(), ""]
ch, fx = m.get("changes", []), m.get("fixes", [])
if ch: out += ["### Mudanças"] + ["- " + x for x in ch] + [""]
if fx: out += ["### Correções"] + ["- " + x for x in fx] + [""]
out += [f"Pacote incremental: **{m.get('version_label', m.get('version',''))}**"
        f" (mínimo {m.get('min_version','-')})."]
print("\n".join(out).strip())
PY
}

# ---------------------------------------------------------------- git ------
git_init() {
  cd "$ROOT"
  if [ ! -d .git ]; then
    git init -q -b main
    ok "repositorio git local criado"
  fi
  git config user.name  "R36S PORT HUB"
  git config user.email "r36s-port-hub@users.noreply.github.com"
  git remote remove origin 2>/dev/null || true
  git remote add origin "https://x-access-token:$TOKEN@github.com/$SLUG.git"
}

guard_leak() {
  local lista="${R36S_BLOQUEIO:-$HOME/.config/r36s-port-hub/bloqueio.txt}"
  [ -f "$lista" ] || return 0
  local achados
  achados="$(git grep --cached -I -n -F -f "$lista" -- . ':!ports.json' 2>/dev/null | head -20 || true)"
  [ -z "$achados" ] && return 0
  c '1;31' "  xx  os arquivos versionados contem termos bloqueados:"
  printf '%s\n' "$achados"
  die "ajuste os arquivos ou desative a checagem com R36S_BLOQUEIO=off"
}

update_version_text() {  # update_version_text "0.4.5 BETA"
  local label="$1"
  # README: selo de versao
  local enc; enc="$(printf '%s' "$label" | sed 's/ /%20/g')"
  sed -i "s/vers%C3%A3o-[0-9.]*%20BETA/vers%C3%A3o-${enc}/g; s/alt=\"Versão [0-9.]* BETA\"/alt=\"Versão ${label}\"/g" "$ROOT/README.md"
  # About (descricao curta do repositorio)
  local base="Central de conteúdo para o console R36S (dArkOSRE): baixe e instale ports de jogos, BIOS de emuladores e ferramentas direto no console, com downloads em segundo plano, PortMaster, temas, Wi-Fi, FTP e cuidados com o microSD. Feito em LÖVE, em PT-BR, EN e RU."
  local desc="v${label} — ${base}"
  local payload
  payload="$(python3 -c 'import json,sys; print(json.dumps({"description": sys.argv[1]}))' "$desc")"
  if api PATCH "/repos/$SLUG" "$payload" >/dev/null 2>&1; then
    ok "descrição da versão atualizada para $label"
  else
    warn "não consegui atualizar a descrição do repositório"
  fi
}

git_push() {  # git_push "mensagem"
  cd "$ROOT"
printf 'dist/\nbuild/\n*.token\n.env\n/catalog.json\n/catalogos/\n/catalogo/\n/bios_url.txt\n/catalog_url.txt\n/es_themes_url.txt\n/update_url.txt\n' > .gitignore
  git add -A
  guard_leak || exit 1
  if git diff --cached --quiet; then
    info "nada novo para commitar"
  else
    git commit -q -m "$1"
    ok "commit: $1"
  fi
  git push -q origin main
  ok "enviado para github.com/$SLUG"
}

# ------------------------------------------------------------- comandos ----
cmd_links() { show_links; }

cmd_setup() {
  local final_dir="$1"
  load_token
  local user
  user="$(api GET /user | jget '.login')"
  [ -n "$user" ] || die "token invalido"
  [ "$SLUG" = "USUARIO/r36s-port-hub" ] && die "defina o repositorio: R36S_SLUG=usuario/repo ./publicar.sh setup ..."
  info "autenticado como $user"
  if [ -z "$(api GET "/repos/$SLUG" | jget '.full_name')" ]; then
    api POST /user/repos "$(python3 -c '
import json, sys
print(json.dumps({"name": sys.argv[1].split("/")[1], "private": False,
  "description": "Central de conteúdo para o console R36S (dArkOSRE): baixe e instale ports de jogos, BIOS de emuladores e ferramentas direto no console, com downloads em segundo plano, PortMaster, temas, Wi-Fi, FTP e cuidados com o microSD. Feito em LÖVE, em PT-BR, EN e RU.",
  "has_issues": True, "has_wiki": False, "has_projects": False}))' "$SLUG")" >/dev/null
    ok "repositorio criado"
  else
    info "repositorio ja existe"
  fi
  # topicos (ajudam a achar o repositorio nas buscas)
  api PUT "/repos/$SLUG/topics" '{"names":["r36s","darkos","arkos","portmaster","love2d","retro-handheld","emulation","bios"]}' >/dev/null \
    && ok "topicos atualizados" || warn "nao consegui atualizar os topicos"
  # links reais no README/update.json
  sed -i "s|USUARIO/r36s-port-hub|$SLUG|g" "$ROOT/README.md" 2>/dev/null || true
  sed -i "s|USUARIO/r36s-port-hub|$SLUG|g" "$ROOT/update.json" 2>/dev/null || true

  git_init
  local up full src
  up="$(pick_file "$final_dir/UPDATE" 'R36S-PORT-HUB-update*.zip' '*.zip')" 2>/dev/null || true
  if [ -z "${up:-}" ]; then up="$(pick_file "$final_dir" 'R36S-PORT-HUB-update*.zip')"; fi
  full="$(pick_file "$final_dir/FINAL" 'R36S-PORT-HUB-BETA.zip' 'R36S-PORT-HUB.zip')" \
    || full="$(pick_file "$final_dir" 'R36S-PORT-HUB*.zip' | head -1)"
  src="$(pick_file "$final_dir/FINAL" '*codigo-fonte*.zip')" \
    || src="$(pick_file "$final_dir" '*codigo-fonte*.zip')"

  local tjson; tjson="$(pick_file "$final_dir" 'temas.json')"
  cp "$tjson" "$ROOT/temas.json"

  local man ver label body
  man="$(manifest_from_zip "$up")"
  ver="$(printf '%s' "$man" | jget '.version')"
  label="$(printf '%s' "$man" | jget '.version_label')"
  body="$(release_body "$man")"

  mkdir -p "$DIST"
  cp "$up"   "$DIST/$UP_NAME"
  cp "$full" "$DIST/$FULL_NAME"
  cp "$src"  "$DIST/$SRC_NAME"
  write_update_json "$DIST/$UP_NAME" "$man"

  update_version_text "$label"
  git_push "R36S PORT HUB $label"
  local rid; rid="$(ensure_release "v$ver" "R36S PORT HUB $label" "$body")"
  [ -n "$rid" ] || die "nao consegui criar a release"
  upload_asset "$rid" "$DIST/$UP_NAME"   "$UP_NAME"
  upload_asset "$rid" "$DIST/$FULL_NAME" "$FULL_NAME"
  upload_asset "$rid" "$DIST/$SRC_NAME"  "$SRC_NAME"
  ok "publicado: v$ver"
  show_links
}

cmd_update() {
  local arg="$1"
  load_token
  local zip man ver label body rid
  zip="$(pick_file "$arg" 'R36S-PORT-HUB-update*.zip' '*.zip')"
  man="$(manifest_from_zip "$zip")"
  [ -n "$man" ] || die "o zip nao tem update_manifest.json"
  ver="$(printf '%s' "$man" | jget '.version')"
  label="$(printf '%s' "$man" | jget '.version_label')"
  body="$(release_body "$man")"
  info "atualizacao $label ($(basename "$zip"))"

  mkdir -p "$DIST"
  cp "$zip" "$DIST/$UP_NAME"
  write_update_json "$DIST/$UP_NAME" "$man"

  # anexos do pacote completo/fonte da versao anterior continuam validos:
  # a nova release recebe o update; se existir a mesma versao, os anexos sao refeitos
  git_init
  update_version_text "$label"
  git_push "Atualização $label"

  rid="$(release_info "v$ver")"
  if [ -n "$rid" ]; then
    warn "release v$ver ja existe; os anexos serao substituidos"
  else
    rid="$(ensure_release "v$ver" "R36S PORT HUB $label" "$body")"
  fi
  [ -n "$rid" ] || die "nao consegui criar a release"
  upload_asset "$rid" "$DIST/$UP_NAME" "$UP_NAME"
  ok "publicado: v$ver"
  show_links
}

cmd_final() {
  local arg="$1"
  load_token
  local full src ver label body rid tag man
  full="$(pick_file "$arg" 'R36S-PORT-HUB-BETA.zip' 'R36S-PORT-HUB.zip' '*.zip')"
  info "pacote completo: $(basename "$full")"

  # codigo-fonte sempre refeito a partir do repositorio local
  mkdir -p "$DIST"; rm -f "$DIST/$SRC_NAME"
  ( cd "$ROOT" && git archive --format=zip --prefix="R36S-PORT-HUB-codigo-fonte/" -o "$DIST/$SRC_NAME" HEAD ) \
    || die "git archive falhou (faca o setup primeiro)"
  ok "codigo-fonte gerado"

  ver="$(grep -oP 'C\.VERSION_NUM\s*=\s*"\K[^"]+' "$ROOT/src/config.lua" | head -1)"
  label="$(grep -oP 'C\.VERSION\s*=\s*L\("\K[^"]+' "$ROOT/src/config.lua" | head -1)"
  update_version_text "$label"
  tag="v$ver"
  rid="$(release_info "$tag")"
  if [ -z "$rid" ]; then
    man="$(python3 -c 'import json,sys;print(json.dumps({"description":"Pacote completo "+sys.argv[1],"changes":[],"fixes":[],"version":sys.argv[2],"version_label":sys.argv[1]}))' "$label" "$ver")"
    rid="$(ensure_release "$tag" "R36S PORT HUB $label" "$(release_body "$man")")"
  fi
  [ -n "$rid" ] || die "nao consegui criar a release"
  cp "$full" "$DIST/$FULL_NAME"
  upload_asset "$rid" "$DIST/$FULL_NAME" "$FULL_NAME"
  upload_asset "$rid" "$DIST/$SRC_NAME"  "$SRC_NAME"
  ok "pacote completo e fonte publicados em $tag"
  show_links
}

cmd_temas() {
  local arg="$1"
  load_token
  local f
  f="$(pick_file "$arg" 'temas.json' '*.json')"
  python3 -c 'import json,sys;json.load(open(sys.argv[1]))' "$f" \
    || die "JSON invalido: $f"
  cp "$f" "$ROOT/temas.json"
  ok "temas.json atualizado ($(jget '.title' < "$f"); $(jget '.updated' < "$f"))"
  git_init
  git_push "temas.json $(jget '.updated' < "$f")"
  show_links
}

# ---------------------------------------------------------------- main ------
case "${1:-links}" in
  links)  show_links ;;
  setup)  [ $# -ge 2 ] || die "uso: ./publicar.sh setup <pasta-final>";  cmd_setup "$2" ;;
  update) [ $# -ge 2 ] || die "uso: ./publicar.sh update <zip|pasta>";   cmd_update "$2" ;;
  final)  [ $# -ge 2 ] || die "uso: ./publicar.sh final <zip|pasta>";    cmd_final "$2" ;;
  temas)  [ $# -ge 2 ] || die "uso: ./publicar.sh temas <temas.json>";   cmd_temas "$2" ;;
  *)      die "comando desconhecido: $1 (use links|setup|update|final|temas)" ;;
esac
