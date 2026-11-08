#!/usr/bin/env bash

# Enumerate exported names only: never serialize inherited credential values.
sharingan_scrub_test_environment() {
  local name
  while IFS= read -r name; do
    # Explicit non-secret controls and build search paths (_PAT also matches _PATH).
    # Do not allow SHARINGAN_* wholesale; provider credentials use that prefix too.
    case "$name" in
      SHARINGAN_ALLOW_TEST_KEYCHAIN_ACCESS|SHARINGAN_SUPPRESS_TEST_KEYCHAIN_ACCESS|\
      SHARINGAN_DISABLE_KEYCHAIN_ACCESS|SHARINGAN_USE_LOCAL_SWEETCOOKIEKIT|\
      LD_LIBRARY_PATH|DYLD_LIBRARY_PATH|DYLD_FRAMEWORK_PATH|LIBRARY_PATH|PKG_CONFIG_PATH) continue ;;
    esac
    if [[ "$name" =~ [Tt][Oo][Kk][Ee][Nn]|[Kk][Ee][Yy]|[Ss][Ee][Cc][Rr][Ee][Tt]|[Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd]|[Pp][Aa][Ss][Ss][Ww][Dd]|[Ww][Ee][Bb][Hh][Oo][Oo][Kk]|[Cc][Rr][Ee][Dd][Ee][Nn][Tt][Ii][Aa][Ll]|[Cc][Oo][Oo][Kk][Ii][Ee]|[Pp][Rr][Ii][Vv][Aa][Tt][Ee]|_[Pp][Aa][Tt] ]]; then
      unset "$name"
    fi
  done < <(compgen -e)
}
sharingan_scrub_test_environment
unset -f sharingan_scrub_test_environment

# Inherited by test runners and their CLI children.
export SHARINGAN_TEST_CODEX_FILE_ISOLATION=1
unset SHARINGAN_TEST_CODEX_FILE_FIXTURES
export SHARINGAN_TEST_SESSION_FILE_ISOLATION=1

if [[ "${SHARINGAN_ALLOW_TEST_KEYCHAIN_ACCESS:-}" != "1" ]]; then
  export SHARINGAN_SUPPRESS_TEST_KEYCHAIN_ACCESS=1
fi
