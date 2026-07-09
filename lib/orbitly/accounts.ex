defmodule Orbitly.Accounts do
  use Ash.Domain,
    otp_app: :orbitly

  resources do
    resource Orbitly.Accounts.Token

    resource Orbitly.Accounts.User do
      define :list_users, action: :read
      define :admin_create_user, action: :admin_create
      define :set_admin, action: :set_admin
      define :destroy_user, action: :destroy
    end
  end
end
