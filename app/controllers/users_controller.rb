class UsersController < ApplicationController
  before_filter :prevent_api_access, :only => [:edit, :update, :update_api]
  
  def show
    render :json => {
      :user => @current_user.as_json(:only => [:username, :real_name, :created_at, :updated_at]).
        merge(:preferences => @current_user.preferences.slice(:thread_mode, :time_zone))
    }
  end
  
  def edit
    render 'shared/dialog'
  end
  
  def update
    @current_user.update_attributes(params[:user].except(:username, :real_name))
    Newsgroup.find_each do |newsgroup|
      if not @current_user.unread_in_group?(newsgroup)
        UnreadPostEntry.where(:user_id => @current_user.id, :newsgroup_id => newsgroup.id).delete_all
      end
    end
    UnreadPostEntry.where(
      'user_id = ? and personal_level < ?',
      @current_user.id, @current_user.unread_level
    ).delete_all
  end
  
  def update_api
    if params[:disable]
      @current_user.update_attributes(:api_key => nil, :api_data => nil)
    elsif params[:enable]
      key = SecureRandom.hex(8) until !key.nil? && User.find_by_api_key(key).nil?
      @current_user.update_attributes(:api_key => key, :api_data => nil)
    end
  end
  
  def unread_counts
    render :json => {
      :unread_counts => {
        :normal => @current_user.unread_count,
        :in_thread => @current_user.unread_count_in_thread,
        :in_reply => @current_user.unread_count_in_reply
      }
    }
  end
end
