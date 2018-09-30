# name: discourse-azure-ad
# about: Microsoft Azure Active Directory OAuth support for Discourse
# version: 0.2
# authors: Neil Lalonde, Ahmader
# url: https://github.com/discourse/discourse-azure-ad

require_dependency 'auth/oauth2_authenticator'

gem 'omniauth-azure-oauth2', '0.0.8'

enabled_site_setting :azure_enabled

class AzureAuthenticator < ::Auth::OAuth2Authenticator
  def name
    'azure'
  end
  
  def register_middleware(omniauth)
    if enabled?
      omniauth.provider :azure_oauth2,
                        :name => 'azure',
                        :client_id => SiteSetting.azure_client_id,
                        :client_secret => SiteSetting.azure_client_secret
    end
  end

  def enabled?
    # SiteSetting.azure_enabled
    if SiteSetting.azure_enabled? && defined?(SiteSetting.azure_client_id) && defined?(SiteSetting.azure_client_secret)
      !SiteSetting.azure_client_id.blank? && !SiteSetting.azure_client_secret.blank?
    end
  end

  # def description_for_user(user)
  #   info = AzureUserInfo.find_by(user_id: user.id)
  #   info&.email || info&.username || ""
  # end

  def can_revoke?
    true
  end

  def revoke(user, skip_remote: false)
    info = AzureUserInfo.find_by(user_id: user.id)
    # info = ::PluginStore.get("azure", "azure_user_#{user['uid']}")
    raise Discourse::NotFound if info.nil?

    # We get a temporary token from google upon login but do not need it, and do not store it.
    # Therefore we do not have any way to revoke the token automatically on google's end

    info.destroy!
    true
  end

  def can_connect_existing_user?
    true
  end

  def after_authenticate(auth_token, existing_account: nil)
    result = Auth::Result.new

    session_info = parse_hash(auth_token)
    azure_hash = session_info[:azure]
    
    result.email = email = session_info[:email]
    result.email_valid = !email.blank?
    result.name = facebook_hash[:name]
    
    result.extra_data = azure_hash
    
    user_info = AzureUserInfo.find_by(azure_user_id: azure_hash[:azure_user_id])

    if existing_account && (user_info.nil? || existing_account.id != user_info.user_id)
      user_info.destroy! if user_info
      result.user = existing_account
      user_info = AzureUserInfo.create!({ user_id: result.user.id }.merge(azure_hash))
    else
      result.user = user_info&.user
    end

    if !result.user && !email.blank? && result.user = User.find_by_email(email)
      AzureUserInfo.create!({ user_id: result.user.id }.merge(azure_hash))
    end
    
    user_info.update_columns(azure_hash) if user_info

    if info = auth_token['info'].present?
      email = auth_token['info']['email']
      if email.present?
        result.email = email
        result.email_valid = true
      end
    end
    result
  end

  def after_create_account(user, auth_token)
    extra_data = auth_token[:extra_data]
    AzureUserInfo.create!({ user_id: user.id }.merge(extra_data))

    true
  end

  def plugin_store_azure_user(azure_user_id, discourse_user_id)
    ::PluginStore.set("azure", "azure_user_#{azure_user_id}", {user_id: discourse_user_id })
  end
  
  protected

  def parse_hash(auth_token)
    raw_info = auth_token["extra"]["raw_info"]
    info = auth_token["info"]
    email = auth_token["info"][:email]
    
    
    {
      azure: {
        azure_user_id: auth_token[:uid] || raw_info[:sub],
        email: email,
        first_name: raw_info[:first_name],
        last_name: raw_info[:last_name],
        name: raw_info[:name]
      },
      email: email,
      email_valid: true
    }

  end

end

# title = GlobalSetting.try(:azure_title) || "Azure AD"
# button_title = GlobalSetting.try(:azure_title) || "with Azure AD"

# title = SiteSetting.try(:azure_title) || "Azure AD"
# button_title = SiteSetting.try(:azure_button_title) || "with Azure AD"

auth_provider :title => "azure_button_title",
              :enabled_setting => "azure_enabled",
              :title_setting => "azure_button_title",
              :authenticator => AzureAuthenticator.new('azure'),
              :message => "Authorizing with Azure AD (make sure pop up blockers are not enabled)",
              :frame_width => 725,
              :frame_height => 500,
              :background_color => '#71B1D1'

register_css <<CSS

.btn-social.azure {
  background: #71B1D1;
}
.btn-social.azure::before {
  content: $fa-var-windows;
}
CSS
