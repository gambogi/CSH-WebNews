module Authentication
  extend ActiveSupport::Concern

  private

  def authenticate_user!
    if user_authenticated?
      update_or_create_user!
    else
      render 'shared/authenticate', layout: false
    end
  end

  def authenticated_username
    request.env[ENV_USERNAME]
  end

  def update_or_create_user!
    user = User.find_or_initialize_by(username: authenticated_username)
    user.real_name = request.env[ENV_REALNAME]
    user.save!
  end

  def user_authenticated?
    authenticated_username.present?
  end
end