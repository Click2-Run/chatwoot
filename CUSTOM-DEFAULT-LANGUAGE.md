# Custom default language (pt_BR)

Forces every newly created **account (organization)** and **user** to start
with the locale set to `pt_BR` (Português Brasileiro) directly in the
database, regardless of the browser's `Accept-Language`, query string, or
OmniAuth/Logto claims at signup time. The locale can still be changed
later from the UI by the user (Profile Settings) or by an admin (Account
Settings → General).

## Why this exists

Chatwoot's stock behavior reads `I18n.locale` at the moment a row is
inserted, which in turn comes from the request's `Accept-Language` header
(via `SwitchLocale`). For a Brazilian-Portuguese-first install
(Própria Cloud), this means an English browser would persist `locale=en`
on the row even though the runtime fallback (`DEFAULT_LOCALE=pt_BR`)
re-renders pages in pt_BR — leaving every newly issued email, CSAT, and
help-center context in English until the user manually flips the toggle.

The customization writes `pt_BR` proactively at INSERT time so the DB row
itself is correct from second zero.

## Behavior summary

| Surface              | Default before | Default after      | Where it's stored                |
| :------------------- | :------------- | :----------------- | :------------------------------- |
| Account (org)        | `en` (enum 0)  | `pt_BR` (enum 16)  | `accounts.locale`                |
| User UI              | unset / browser| `pt_BR`            | `users.ui_settings -> 'locale'`  |
| Anonymous fallback   | `en`           | `pt_BR`            | `DEFAULT_LOCALE` env var         |

Existing rows are **not** rewritten — only new accounts and new users.

## Two layers, two responsibilities

This customization works alongside the upstream `DEFAULT_LOCALE` env. The
two are deliberately separate:

- **`DEFAULT_LOCALE` (env, runtime fallback)** — used by
  `app/controllers/concerns/switch_locale.rb` when no user/account is in
  scope (widget, anonymous help-center, error pages, mailer warm-up).
  Only affects what gets *rendered*, not what gets *stored*.
- **Proactive DB writes (this customization)** — set the column on
  INSERT, so every entry point (signup form, OmniAuth/Logto, agent
  invite, super-admin create) persists `pt_BR` independent of request
  context.

## Files changed

### `app/builders/account_builder.rb`

Stops sourcing the new account's locale from `I18n.locale`. The new
helper returns `pt_BR` by default, with an env override for branded
non-Portuguese installs.

```ruby
def create_account
  @account = Account.create!(name: account_name, locale: default_account_locale)
  Current.account = @account
  enable_default_account_features
  @account
end

def default_account_locale
  ENV.fetch('DEFAULT_ACCOUNT_LOCALE', 'pt_BR')
end
```

### `app/models/user.rb`

Adds a `before_create` callback that seeds `ui_settings.locale` if the
caller has not already set one. Runs for every `User.create` path —
form signup, OmniAuth/Logto callback, agent invitation, super-admin
creation.

```ruby
before_validation :set_password_and_uid, on: :create
before_create :set_default_ui_locale
after_destroy :remove_macros

# …

def set_default_ui_locale
  self.ui_settings ||= {}
  return if ui_settings['locale'].present?

  ui_settings['locale'] = ENV.fetch('DEFAULT_USER_LOCALE', 'pt_BR')
end
```

### `.env` and `.env.example`

`DEFAULT_LOCALE` is now active (uncommented) at `pt_BR` so the runtime
fallback layer matches. Two new optional escape-hatch vars are
documented but commented:

```bash
# Runtime fallback locale for anonymous pages (widget, emails before
# the user is resolved, error pages). New accounts and users are forced
# to pt_BR by AccountBuilder/User#set_default_ui_locale regardless of
# this var; override DEFAULT_ACCOUNT_LOCALE / DEFAULT_USER_LOCALE to
# change the proactive creation default per environment.
DEFAULT_LOCALE=pt_BR
# DEFAULT_ACCOUNT_LOCALE=pt_BR
# DEFAULT_USER_LOCALE=pt_BR
```

## Environment variables

| Variable                 | Default  | Effect                                                                                          |
| :----------------------- | :------- | :---------------------------------------------------------------------------------------------- |
| `DEFAULT_LOCALE`         | `pt_BR`  | Runtime fallback when no user/account is in scope. Upstream Chatwoot behavior.                  |
| `DEFAULT_ACCOUNT_LOCALE` | `pt_BR`  | Locale written to `accounts.locale` on creation. Overrides hard-coded default if exported.      |
| `DEFAULT_USER_LOCALE`    | `pt_BR`  | Locale written to `users.ui_settings.locale` on creation. Overrides hard-coded default if set.  |

Set the override pair to e.g. `en` to ship a non-Portuguese branded
install without code changes.

## Verification

After restarting the Rails container (`docker compose restart rails`),
exercise the full builder path and confirm both columns hit the DB:

```bash
docker compose exec -T rails bundle exec rails runner '
require "securerandom"
suffix = SecureRandom.hex(4)
user, account = AccountBuilder.new(
  account_name: "LocaleTest #{suffix}",
  email: "locale-#{suffix}@test.local",
  user_full_name: "Locale Tester",
  user_password: "Password123!",
  confirmed: true
).perform
puts "ACCOUNT_LOCALE=#{account.locale}"
puts "USER_UI_LOCALE=#{user.ui_settings.inspect}"
account.destroy!
user.destroy!
'
```

Expected output:

```
ACCOUNT_LOCALE=pt_BR
USER_UI_LOCALE={"locale" => "pt_BR"}
```

## Backfilling existing rows (optional)

If you want previously created accounts and users to also flip to
`pt_BR`, run once:

```ruby
# Account.locale is an integer enum — pt_BR is index 16
Account.where(locale: 'en').update_all(locale: 16)

User.find_each do |u|
  next if u.ui_settings.present? && u.ui_settings['locale'].present?
  u.update_column(:ui_settings, (u.ui_settings || {}).merge('locale' => 'pt_BR'))
end
```

This is opt-in and never runs automatically — it would overwrite genuine
user choices made before the customization landed.

## Out of scope (intentionally)

- **Help-center portals (`portals.config.default_locale`)** are not
  forced. They are configured per portal in the help-center admin UI
  and may legitimately need to ship in `en` for non-Brazilian
  audiences.
- **Email templates (`email_templates.locale`)** are not forced. They
  inherit from the account's locale at render time.
- **Existing rows** are not rewritten — see the optional backfill
  snippet above.
