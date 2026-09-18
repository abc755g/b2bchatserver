#!/usr/bin/env python3
"""Правка config.yaml для matrix-authentication-service.

Базовый файл делает сам MAS (`mas-cli config generate`) — здесь только
подставляются адреса, секреты и, если задан, внешний OIDC-провайдер.
Скрипт идемпотентен: повторный запуск не плодит блоки и не трогает
`secrets.keys`, поэтому сессии пользователей переживают перенастройку.
"""

import argparse
import pathlib
import re
import secrets
import sys

ULID_ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"


def new_ulid() -> str:
    """26 символов Crockford base32 — формат идентификатора провайдера в MAS."""
    return "".join(secrets.choice(ULID_ALPHABET) for _ in range(26))


def existing_provider_id(text: str) -> str:
    match = re.search(r"(?m)^\s+-\s+id:\s*([0-9A-HJKMNP-TV-Z]{26})\s*$", text)
    return match.group(1) if match else ""


def replace_block(text: str, key: str, block: str) -> str:
    """Заменить блок верхнего уровня целиком либо дописать его в конец."""
    pattern = re.compile(r"(?m)^%s:\n(?:[ \t]+.*\n|\n(?=[ \t]))*" % re.escape(key))
    if pattern.search(text):
        return pattern.sub(block, text, count=1)
    return text.rstrip("\n") + "\n\n" + block


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("config")
    ap.add_argument("--public-base", required=True)
    ap.add_argument("--db-uri", required=True)
    ap.add_argument("--server-name", required=True)
    ap.add_argument("--mas-secret", required=True)
    ap.add_argument("--password-registration", choices=["true", "false"], default="false")
    ap.add_argument("--oidc-issuer", default="")
    ap.add_argument("--oidc-client-id", default="")
    ap.add_argument("--oidc-name", default="SSO")
    args = ap.parse_args()

    path = pathlib.Path(args.config)
    if not path.is_file():
        print(f"не найден {path}", file=sys.stderr)
        return 1
    text = path.read_text()

    text = re.sub(r"(?m)^  public_base: .*", f"  public_base: {args.public_base}", text, count=1)
    text = re.sub(r"(?m)^  issuer: .*", f"  issuer: {args.public_base}", text, count=1)
    text = re.sub(r"(?m)^  uri: postgresql://.*", f"  uri: {args.db_uri}", text, count=1)

    text = replace_block(text, "matrix", (
        "matrix:\n"
        "  kind: synapse\n"
        f"  homeserver: {args.server_name}\n"
        f"  secret: {args.mas_secret}\n"
        "  endpoint: http://synapse:8008/\n"
    ))

    # Регистрация OAuth-клиентов (внешние сервисы, Element Web/X) — по спецификации
    # Matrix она динамическая: клиент сам присылает свои метаданные. Дефолты MAS
    # это разрешают, но задаём явно, чтобы обновление MAS не поменяло их молча:
    # только https, redirect_uri на том же хосте, что client_uri; контакт
    # необязателен — многие клиенты его не шлют.
    text = replace_block(text, "policy", (
        "policy:\n"
        "  data:\n"
        "    client_registration:\n"
        "      allow_insecure_uris: false\n"
        "      allow_host_mismatch: false\n"
        "      allow_missing_contacts: true\n"
    ))

    # Локальные пароли остаются: без них у администратора сервера нет входа,
    # если внешний провайдер недоступен. Саморегистрацию открывает отдельный флаг.
    # Правим только строку enabled — schemes и minimum_complexity ставит сам MAS.
    text = re.sub(r"(?m)^passwords:\n  enabled: .*", "passwords:\n  enabled: true", text, count=1)

    reg = f"  password_registration_enabled: {args.password_registration}"
    if re.search(r"(?m)^account:", text):
        if re.search(r"(?m)^  password_registration_enabled:", text):
            text = re.sub(r"(?m)^  password_registration_enabled: .*", reg, text, count=1)
        else:
            text = re.sub(r"(?m)^account:", "account:\n" + reg, text, count=1)
    else:
        text = text.rstrip("\n") + "\n\naccount:\n" + reg + "\n"

    provider_id = existing_provider_id(text)
    text = re.sub(r"(?m)^upstream_oauth2:\n(?:[ \t].*\n|\n(?=[ \t]))*", "", text)

    if args.oidc_issuer and args.oidc_client_id:
        provider_id = provider_id or new_ulid()
        # http-issuer бывает только на стенде: строгий OIDC требует https
        discovery = "    discovery_mode: insecure\n" if args.oidc_issuer.startswith("http://") else ""
        block = (
            "upstream_oauth2:\n"
            "  providers:\n"
            f"  - id: {provider_id}\n"
            f"    human_name: {args.oidc_name}\n"
            f"    issuer: {args.oidc_issuer}\n"
            f"    client_id: {args.oidc_client_id}\n"
            "    token_endpoint_auth_method: none\n"
            f"{discovery}"
            "    scope: openid profile email\n"
            "    claims_imports:\n"
            "      localpart:\n"
            "        action: require\n"
            '        template: "{{ user.preferred_username }}"\n'
            "      displayname:\n"
            "        action: suggest\n"
            '        template: "{{ user.name }}"\n'
            "      email:\n"
            "        action: suggest\n"
            '        template: "{{ user.email }}"\n'
        )
        text = re.sub(r"(?m)^matrix:", block + "\nmatrix:", text, count=1)
        print(f"OIDC-провайдер: {args.oidc_issuer} (id {provider_id})")
        print(f"redirect_uri для провайдера: {args.public_base}upstream/callback/{provider_id}")

    path.write_text(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
