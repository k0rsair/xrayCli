#!/usr/bin/env bats

setup() {
  export BATS_TEST_MODE=1
  PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  # shellcheck disable=SC1091
  source "${PROJECT_ROOT}/lib/common.sh"
}

@test "is_valid_fqdn accepts valid domain" {
  is_valid_fqdn "vpn.example.com"
}

@test "is_valid_fqdn rejects invalid domain" {
  ! is_valid_fqdn "not-a-domain"
}

@test "mask_secret hides value" {
  [[ "$(mask_secret "abcdefgh1234")" == ***1234 ]]
}
