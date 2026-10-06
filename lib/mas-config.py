#!/usr/bin/env python3
"""Правка config.yaml для matrix-authentication-service.

Базовый файл делает сам MAS (`mas-cli config generate`) — здесь только
подставляются адреса, секреты и внешние OIDC-провайдеры: IdP компании
и B2B-портал, каждый по отдельности.
Скрипт идемпотентен: повторный запуск не плодит блоки и не трогает
`secrets.keys`, поэтому сессии пользователей переживают перенастройку.
"""

import argparse
import pathlib
import re
import secrets
import sys

ULID_ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"

# id провайдера «B2B-портал» один на все установки: из него MAS строит
# redirect_uri (<issuer MAS>upstream/callback/<id>), и портал, регистрируя
# клиента для сервера компании, вычисляет адрес сам — переписывать его вручную
# из консоли администратору не нужно. Менять нельзя: по id MAS хранит привязки
# аккаунтов к порталу, новый id их осиротит.
PORTAL_PROVIDER_ID = "01B2BP0RTA0000000000000000"


def new_ulid() -> str:
    """26 символов Crockford base32 — формат идентификатора провайдера в MAS."""
    return "".join(secrets.choice(ULID_ALPHABET) for _ in range(26))


def existing_provider_id(text: str) -> str:
    """id провайдера компании из прошлого запуска — портал не в счёт."""
    for match in re.finditer(r"(?m)^\s+-\s+id:\s*([0-9A-HJKMNP-TV-Z]{26})\s*$", text):
        if match.group(1) != PORTAL_PROVIDER_ID:
            return match.group(1)
    return ""


def provider_block(provider_id: str, name: str, issuer: str, client_id: str,
                   on_conflict: str = "", scope: str = "openid profile email",
                   localpart: str = '"{{ user.preferred_username }}"') -> str:
    # http-issuer бывает только на стенде: строгий OIDC требует https
    discovery = "    discovery_mode: insecure\n" if issuer.startswith("http://") else ""
    conflict = f"        on_conflict: {on_conflict}\n" if on_conflict else ""
    return (
        f"  - id: {provider_id}\n"
        f"    human_name: {name}\n"
        f"    issuer: {issuer}\n"
        f"    client_id: {client_id}\n"
        "    token_endpoint_auth_method: none\n"
        f"{discovery}"
        f"    scope: {scope}\n"
        "    claims_imports:\n"
        "      localpart:\n"
        "        action: require\n"
        f"        template: {localpart}\n"
        f"{conflict}"
        "      displayname:\n"
        "        action: suggest\n"
        '        template: "{{ user.name }}"\n'
        "      email:\n"
        "        action: suggest\n"
        '        template: "{{ user.email }}"\n'
    )


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
    ap.add_argument("--passwords", choices=["true", "false"], default="true")
    ap.add_argument("--oidc-issuer", default="")
    ap.add_argument("--oidc-client-id", default="")
    ap.add_argument("--oidc-name", default="SSO")
    ap.add_argument("--portal-issuer", default="")
    ap.add_argument("--portal-client-id", default="")
    ap.add_argument("--portal-name", default="B2B-портал")
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

    provider_id = existing_provider_id(text)
    # Вместе с блоком — и пустую строку после него, которую дописывает вставка
    # ниже: иначе каждый прогон добавлял бы перед matrix: ещё одну.
    text = re.sub(r"(?m)^upstream_oauth2:\n(?:[ \t].*\n|\n(?=[ \t]))*\n?", "", text)

    providers = []
    if args.oidc_issuer and args.oidc_client_id:
        provider_id = provider_id or new_ulid()
        providers.append(provider_block(provider_id, args.oidc_name,
                                        args.oidc_issuer, args.oidc_client_id))
        print(f"OIDC-провайдер: {args.oidc_issuer} (id {provider_id})")
        print(f"redirect_uri для провайдера: {args.public_base}upstream/callback/{provider_id}")

    # Портал — дополнительный способ входа, не замена: пароли и IdP компании
    # остаются, и при недоступности портала пропадает только его кнопка.
    # Логин портал присылает в claim b2b_mxids (scope b2b_matrix) — только тот,
    # владение которым сотрудник уже подтвердил входом на этот сервер, а без
    # подтверждения сам не пускает. Поэтому вход связывается с существующим
    # аккаунтом без пароля (on_conflict: set — если у аккаунта ещё нет привязки
    # к порталу) и новых аккаунтов через портал не появляется.
    if args.portal_issuer and args.portal_client_id:
        key = args.server_name.replace("\\", "").replace('"', "")
        providers.append(provider_block(
            PORTAL_PROVIDER_ID, args.portal_name, args.portal_issuer, args.portal_client_id,
            on_conflict="set",
            scope="openid profile email b2b_matrix",
            localpart="'{{ user.b2b_mxids[\"%s\"] }}'" % key,
        ))
        print(f"Вход через B2B-портал: {args.portal_issuer}")

    if providers:
        block = "upstream_oauth2:\n  providers:\n" + "".join(providers)
        text = re.sub(r"(?m)^matrix:", block + "\nmatrix:", text, count=1)

    # Вход по паролю — выбор компании (--passwords), по умолчанию включён.
    # Выключить его можно только рядом с другим поставщиком входа: иначе на
    # сервер не вошёл бы никто, включая администратора. Без паролей нет и
    # саморегистрации по паролю — MAS её не допускает.
    passwords = args.passwords
    if passwords == "false" and not providers:
        print("Вход по паролю включён: другого способа входа на сервер не осталось", file=sys.stderr)
        passwords = "true"
    registration = args.password_registration if passwords == "true" else "false"

    # Правим только строку enabled — schemes и minimum_complexity ставит сам MAS:
    # хеши паролей остаются, и повторное включение возвращает прежние пароли.
    text = re.sub(r"(?m)^passwords:\n  enabled: .*", f"passwords:\n  enabled: {passwords}", text, count=1)

    reg = f"  password_registration_enabled: {registration}"
    if re.search(r"(?m)^account:", text):
        if re.search(r"(?m)^  password_registration_enabled:", text):
            text = re.sub(r"(?m)^  password_registration_enabled: .*", reg, text, count=1)
        else:
            text = re.sub(r"(?m)^account:", "account:\n" + reg, text, count=1)
    else:
        text = text.rstrip("\n") + "\n\naccount:\n" + reg + "\n"

    path.write_text(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
