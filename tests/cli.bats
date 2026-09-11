#!/usr/bin/env bats

load helpers/setup

setup() {
  setup_codex_account
}

@test "no arguments prints help" {
  run "$CODEX_ACCOUNT"
  [ "$status" -eq 0 ]
  [[ "$output" == *'Usage:'* ]] || return 1
}

@test "--version prints name and version" {
  run "$CODEX_ACCOUNT" --version
  [ "$status" -eq 0 ]
  [[ "$output" == 'codex-account '* ]] || return 1
}

@test "unknown command exits 2" {
  run "$CODEX_ACCOUNT" nope
  [ "$status" -eq 2 ]
  [[ "$output" == *'unknown command'* ]] || return 1
}

@test "unknown option exits 2" {
  run "$CODEX_ACCOUNT" --nope
  [ "$status" -eq 2 ]
  [[ "$output" == *'unknown option'* ]] || return 1
}

@test "save without a name is a usage error" {
  run "$CODEX_ACCOUNT" save
  [ "$status" -eq 1 ]
  [[ "$output" == *'usage:'* ]] || return 1
}

@test "save with extra arguments is a usage error" {
  run "$CODEX_ACCOUNT" save one two
  [ "$status" -eq 1 ]
  [[ "$output" == *'usage:'* ]] || return 1
}

@test "current exits non-zero when signed out" {
  run "$CODEX_ACCOUNT" current
  [ "$status" -eq 1 ]
  [[ "$output" == *'Not signed in'* ]] || return 1
}

@test "list explains itself when empty" {
  run "$CODEX_ACCOUNT" list
  [ "$status" -eq 0 ]
  [[ "$output" == *'No profiles saved yet'* ]] || return 1
}

@test "list --json emits valid redacted profile JSON" {
  sign_in_as 'work@example.com' 'acct-work'
  "$CODEX_ACCOUNT" save work
  sign_in_as 'personal@example.com' 'acct-personal'
  "$CODEX_ACCOUNT" save personal

  run "$CODEX_ACCOUNT" list --json
  [ "$status" -eq 0 ]

  printf '%s\n' "$output" |
    jq -e '
      type == "array" and
      length == 2 and
      all(.[]; ((keys | sort) == ["active", "email", "name"]) and
        (.name | type == "string") and
        (.email | type == "string") and
        (.active | type == "boolean")) and
      (map(select(.active)) | length == 1) and
      any(.[]; .name == "personal" and .email == "personal@example.com" and .active == true) and
      any(.[]; .name == "work" and .email == "work@example.com" and .active == false)
    ' >/dev/null || return 1
}

@test "list --json includes only the optional local usage label" {
  sign_in_as 'work@example.com' 'acct-work'
  "$CODEX_ACCOUNT" save work

  mkdir -p "$CODEX_ACCOUNT_HOME/usage"
  printf '{"captured_at":1,"weekly":{"used_percent":25,"resets_at":0}}\n' >"$CODEX_ACCOUNT_HOME/usage/work.json"

  run "$CODEX_ACCOUNT" list --json
  [ "$status" -eq 0 ]

  printf '%s\n' "$output" |
    jq -e '
      type == "array" and
      length == 1 and
      (.[0] | (keys | sort) == ["active", "email", "name", "usage"]) and
      .[0].usage == "75% wk"
    ' >/dev/null || return 1
}

@test "list --json never exposes token account id or credential path data" {
  sign_in_as 'work@example.com' 'acct-work' 'rt-super-secret'
  "$CODEX_ACCOUNT" save work
  sign_in_as 'personal@example.com' 'acct-personal' 'rt-also-secret'
  "$CODEX_ACCOUNT" save personal

  run "$CODEX_ACCOUNT" list --json
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e . >/dev/null || return 1

  [[ "$output" != *'rt-super-secret'* ]] || return 1
  [[ "$output" != *'rt-also-secret'* ]] || return 1
  [[ "$output" != *'access_token'* ]] || return 1
  [[ "$output" != *'refresh_token'* ]] || return 1
  [[ "$output" != *'id_token'* ]] || return 1
  [[ "$output" != *'OPENAI_API_KEY'* ]] || return 1
  [[ "$output" != *'acct-work'* ]] || return 1
  [[ "$output" != *'acct-personal'* ]] || return 1
  [[ "$output" != *"$CODEX_HOME"* ]] || return 1
  [[ "$output" != *"$CODEX_ACCOUNT_HOME"* ]] || return 1
  [[ "$output" != *'auth.json'* ]] || return 1
  [[ "$output" != *'/profiles/'* ]] || return 1
}

@test "list --json rejects control-byte profile names through existing validation" {
  sign_in_as 'work@example.com' 'acct-work'

  run "$CODEX_ACCOUNT" save "$(printf 'ok\nEVIL')"
  [ "$status" -ne 0 ]

  run "$CODEX_ACCOUNT" list --json
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e 'type == "array" and length == 0' >/dev/null || return 1
}

@test "list --json emits valid JSON with invalid bytes in existing profile data" {
  mkdir -p "$CODEX_ACCOUNT_HOME/profiles"

  make_credential "$(printf 'bad\377@example.com')" 'acct-bad' >"$CODEX_ACCOUNT_HOME/profiles/badfile.json"
  chmod 600 "$CODEX_ACCOUNT_HOME/profiles"/*.json

  run "$CODEX_ACCOUNT" list --json
  [ "$status" -eq 0 ]

  printf '%s\n' "$output" |
    jq -e '
      type == "array" and
      length == 1 and
      (.[0] | (keys | sort) == ["active", "email", "name"]) and
      .[0].name == "badfile" and
      .[0].email == "bad@example.com" and
      .[0].active == false
    ' >/dev/null || return 1
}

@test "list --json escapes quotes and backslashes in display labels" {
  local claims

  claims="$(printf '%s' '{"email":"quote\"slash\\@example.com","email_verified":true}' | base64url)"
  printf '{"auth_mode":"chatgpt","OPENAI_API_KEY":null,"tokens":{"id_token":"hdr.%s.sig","access_token":"at-quoted","refresh_token":"rt-quoted","account_id":"acct-quoted"},"last_refresh":"2026-07-24T09:31:00.000Z"}' \
    "$claims" >"$CODEX_HOME/auth.json"
  chmod 600 "$CODEX_HOME/auth.json"
  "$CODEX_ACCOUNT" save quoted

  run "$CODEX_ACCOUNT" list --json
  [ "$status" -eq 0 ]

  printf '%s\n' "$output" |
    jq -e '
      type == "array" and
      length == 1 and
      .[0].name == "quoted" and
      .[0].email == "quote\"slash\\@example.com"
    ' >/dev/null || return 1
}

@test "list --json refuses safely when jq is unavailable" {
  CODEX_ACCOUNT_FAKE_NO_JQ=1
  export CODEX_ACCOUNT_FAKE_NO_JQ
  sign_in_as 'work@example.com' 'acct-work' 'rt-super-secret'
  "$CODEX_ACCOUNT" save work

  run "$CODEX_ACCOUNT" list --json
  [ "$status" -eq 1 ]

  [[ "$output" == *'list --json requires jq'* ]] || return 1
  [[ "$output" == *'install jq'* ]] || return 1
  [[ "$output" != *'rt-super-secret'* ]] || return 1
  [[ "$output" != *'access_token'* ]] || return 1
  [[ "$output" != *'refresh_token'* ]] || return 1
  [[ "$output" != *'id_token'* ]] || return 1
  [[ "$output" != *'OPENAI_API_KEY'* ]] || return 1
  [[ "$output" != *'acct-work'* ]] || return 1
  [[ "$output" != *'work@example.com'* ]] || return 1
  [[ "$output" != *"$CODEX_HOME"* ]] || return 1
  [[ "$output" != *"$CODEX_ACCOUNT_HOME"* ]] || return 1
  [[ "$output" != *'auth.json'* ]] || return 1
  [[ "$output" != *'/profiles/'* ]] || return 1
}

@test "ls --json emits redacted profile JSON" {
  sign_in_as 'work@example.com' 'acct-work'
  "$CODEX_ACCOUNT" save work

  run "$CODEX_ACCOUNT" ls --json
  [ "$status" -eq 0 ]

  printf '%s\n' "$output" |
    jq -e 'type == "array" and length == 1 and .[0].name == "work"' >/dev/null || return 1
}

@test "-- terminates option parsing for list" {
  sign_in_as 'work@example.com' 'acct-work'
  "$CODEX_ACCOUNT" save work

  run "$CODEX_ACCOUNT" list -- --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'work@example.com'* ]] || return 1
  [[ "$output" != '['* ]] || return 1
}

@test "help documents list json and redacted schema" {
  run "$CODEX_ACCOUNT" help
  [ "$status" -eq 0 ]

  [[ "$output" == *'list [--json]'* ]] || return 1
  [[ "$output" == *'With list/ls only, print redacted JSON'* ]] || return 1
  [[ "$output" == *'Requires jq'* ]] || return 1
  [[ "$output" == *'"name":string'* ]] || return 1
  [[ "$output" == *'"email":string'* ]] || return 1
  [[ "$output" == *'"active":boolean'* ]] || return 1
  [[ "$output" == *'"usage"?:string'* ]] || return 1
}

@test "--quiet suppresses informational output" {
  sign_in_as 'work@example.com' 'acct-work'
  run "$CODEX_ACCOUNT" --quiet save work
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "aliases resolve to the same commands" {
  sign_in_as 'work@example.com' 'acct-work'
  run "$CODEX_ACCOUNT" save work
  [ "$status" -eq 0 ]

  run "$CODEX_ACCOUNT" ls
  [ "$status" -eq 0 ]
  [[ "$output" == *'work'* ]] || return 1

  run "$CODEX_ACCOUNT" whoami
  [ "$status" -eq 0 ]
  [[ "$output" == *'work@example.com'* ]] || return 1
}
