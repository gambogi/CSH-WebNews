class PostsController < ApplicationController
  before_filter :get_newsgroup, :only => [:index, :search, :search_entry, :next_unread, :show, :new]
  before_filter :get_post, :except => [:index, :search, :search_entry, :create]
  before_filter :get_newsgroups_for_search, :only => :search_entry
  before_filter :get_newsgroups_for_posting, :only => [:new, :create]
  before_filter :set_list_layout_and_offset, :only => [:index, :search]
  before_filter :set_limit_from_params, :only => [:index, :search]

  def index
    @not_found = true if params[:not_found]
    @flat_mode = true if @current_user.thread_mode == :flat
    
    if params[:from_number]
      post_selected = @newsgroup.posts.find_by_number(params[:from_number])
      if not post_selected
        render :status => :not_found, :json => json_error('post_not_found',
          "Post number '#{params[:from_number]}' in newsgroup '#{params[:newsgroup]}' does not exist") and return
      end
      thread_selected = post_selected
      thread_selected = post_selected.thread_parent if not @flat_mode
      @from_older = (params[:include_older] or not @api_access) ? thread_selected.date : nil
      @from_newer = (params[:include_newer] or not @api_access) ? thread_selected.date : nil
    end
    
    if not @limit
      @limit = (@from_older and @from_newer) ? INDEX_DEF_LIMIT_2 : INDEX_DEF_LIMIT_1
      @limit *= 2 if @flat_mode
    end
    
    @limit += 1
    
    if not (@from_older or @from_newer or thread_selected)
      @from_older = Post.order('date').last.date + 1.second
    end
    
    if @from_older
      date_condition = (params[:older_inclusive] ? 'date <= ?' : 'date < ?')
      if @flat_mode
        @posts_older = @newsgroup.posts.where(date_condition, @from_older).order('date DESC').limit(@limit)
      else
        @posts_older = @newsgroup.posts.
          where("parent_id = ? and #{date_condition}", '', @from_older).
          order('date DESC').limit(@limit)
      end
    end
    
    if @from_newer
      date_condition = (params[:newer_inclusive] ? 'date >= ?' : 'date > ?')
      if @flat_mode
        @posts_newer = @newsgroup.posts.where(date_condition, @from_newer).order('date').limit(@limit).reverse
      else
        @from_newer = @newsgroup.posts.where(:date => @from_newer).first.thread_parent.date
        @posts_newer = @newsgroup.posts.
          where("parent_id = ? and #{date_condition}", '', @from_newer).
          order('date').limit(@limit).reverse
      end
    end
    
    if @posts_older
      @more_older = @posts_older.length > 0 && !@posts_older[@limit - 1].nil?
      @posts_older.delete_at(-1) if @posts_older.length == @limit
    end
    if @posts_newer
      @more_newer = @posts_newer.length > 0 && !@posts_newer[@limit - 1].nil?
      @posts_newer.delete_at(-1) if @posts_newer.length == @limit
    end
    
    if not @flat_mode
      flatten = (@current_user.thread_mode == :hybrid)
      @posts_selected = thread_selected.thread_tree_for_user(@current_user, flatten, @api_access) if thread_selected
      [@posts_older, @posts_newer].each do |posts|
        posts.map!{ |post| post.thread_tree_for_user(@current_user, flatten, @api_access) } if posts
      end
    else
      @posts_selected = {:post => thread_selected} if thread_selected
      [@posts_older, @posts_newer].each do |posts|
        posts.map!{ |post| {:post => post} } if posts
      end
    end
    
    get_next_unread_post
    
    respond_to do |wants|
      wants.js do
        # render 'index'
      end
      wants.json do
        json = {}
        json.merge!({ :posts_selected => @posts_selected }) if @posts_selected
        json.merge!({ :posts_older => @posts_older, :more_older => @more_older }) if @posts_older
        json.merge!({ :posts_newer => @posts_newer, :more_newer => @more_newer }) if @posts_newer
        render :json => json
      end
    end
  end
  
  def search
    @limit = INDEX_DEF_LIMIT_1 * 2 if not @limit
    @limit += 1
    
    conditions, values, error = build_search_conditions
    
    if @from_older
      conditions << 'date < ?'
      values << @from_older
    end
    if not @newsgroup
      conditions << 'newsgroup not like ?'
      values << 'control%'
    end
    if params[:unread] and params[:personal_class]
      min_level = PERSONAL_CODES[params[:personal_class].to_sym]
      if min_level
        conditions << 'unread_post_entries.personal_level >= ?'
        values << min_level
      else
        render :status => :bad_request, :json => json_error('personal_class_invalid',
          "'#{params[:personal_class]}' is not a valid personal class") and return
      end
    end
    
    search_params = params.except(:action, :controller, :source, :commit, :validate, :utf8, :_)
    
    if error
      json_or_form_error(:bad_request, error[:json_id], error[:json_details], error[:form_text]) and return
    elsif params[:validate]
      render :partial => 'search_redirect', :locals => { :search_params => search_params } and return
    end
    
    @search_mode = @flat_mode = true
    if search_params.include?(:starred) and search_params.reject{ |k,v| v.blank? }.length == 1
      @starred_only = true
    end
    
    scope = Post.scoped
    scope = scope.sticky if params[:sticky]
    scope = scope.starred_by_user(@current_user) if params[:starred]
    scope = scope.unread_for_user(@current_user) if params[:unread]
    scope = scope.where(:newsgroup => @newsgroup.name) if @newsgroup
    @posts_older = scope.where(conditions.join(' and '), *values).order('date DESC').limit(@limit)
    @more_older = @posts_older.length > 0 && !@posts_older[@limit - 1].nil?
    @posts_older.delete_at(-1) if @posts_older.length == @limit
    @posts_older.map!{ |post| {:post => post} }
    
    get_next_unread_post
    
    respond_to do |wants|
      wants.js { render 'index' }
      wants.json { render :json => { :posts_older => @posts_older, :more_older => @more_older } }
    end
  end
  
  def search_entry
    render 'shared/dialog'
  end
  
  def next_unread
    get_next_unread_post
    if params[:mark_read]
      was_unread = @next_unread_post.mark_read_for_user(@current_user)
    end
    render :json => {
      :post => @next_unread_post.as_json(:for_user => @current_user, :with_all => true)
    }.merge(params[:mark_read] ? { :was_unread => was_unread } : {})
  end
  
  def show
    respond_to do |wants|
      wants.js do
        @search_mode = (params[:search_mode] ? true : false)
        if @post
          @post_was_unread = @post.mark_read_for_user(@current_user)
          get_next_unread_post
          @admin_cancel = true if @current_user.is_admin? and not @post.authored_by?(@current_user)
        else
          @not_found = true
        end
      end
      
      wants.json do
        if params[:mark_read]
          was_unread = @post.mark_read_for_user(@current_user)
        end
        render :json => {
          :post => @post.as_json(:for_user => @current_user, :with_all => true)
        }.merge(params[:mark_read] ? { :was_unread => was_unread } : {})
      end
    end
  end
  
  def new
    @new_post = Post.new(:newsgroup => @newsgroup)
    if @post
      @new_post.subject = 'Re: ' + @post.subject.sub(/^Re: ?/, '')
      @new_post.body = @post.quoted_body
    end
    render 'shared/dialog'
  end
  
  def create
    post_newsgroups = []
    @sync_error = nil
  
    if params[:post][:subject].blank?
      form_error "You must enter a subject line for your post." and return
    end
    
    newsgroup = @newsgroups.where_posting_allowed.find_by_name(params[:post][:newsgroup])
    if newsgroup.nil?
      form_error "The specified newsgroup is either nonexistent or read-only." and return
    end
    post_newsgroups << newsgroup
    
    if params[:crosspost_to] and params[:crosspost_to] != ''
      crosspost_to = @newsgroups.where_posting_allowed.find_by_name(params[:crosspost_to])
      if crosspost_to.nil?
        form_error "The specified cross-post newsgroup is either nonexistent or read-only." and return
      elsif crosspost_to == newsgroup
        form_error "The specified cross-post newsgroup is the same as the primary newsgroup." and return
      end
      post_newsgroups << crosspost_to
    end
    
    # TODO: Generalize the concept of "extra cross-post newsgroups" as a configuration option
    if params[:crosspost_sysadmin]
      n = @newsgroups.where_posting_allowed.find_by_name('csh.lists.sysadmin')
      if post_newsgroups.include?(n)
        form_error "You specified 'also to csh.lists.sysadmin', but that newsgroup is already selected." and return
      end
      post_newsgroups << n
    end
    
    if params[:crosspost_alumni]
      n = @newsgroups.where_posting_allowed.find_by_name('csh.lists.alumni')
      if post_newsgroups.include?(n)
        form_error "You specified 'also to csh.lists.alumni', but that newsgroup is already selected." and return
      end
      post_newsgroups << n
    end
    
    reply_newsgroup = reply_post = nil
    if params[:post][:reply_newsgroup]
      reply_newsgroup = Newsgroup.find_by_name(params[:post][:reply_newsgroup])
      reply_post = Post.where(:newsgroup => params[:post][:reply_newsgroup],
        :number => params[:post][:reply_number]).first
      if reply_post.nil?
        form_error "The post you are trying to reply to doesn't exist; it may have been canceled. Try refreshing the newsgroup." and return
      end
    end
    
    post_string = Post.build_message(
      :user => @current_user,
      :newsgroups => post_newsgroups.map(&:name),
      :subject => params[:post][:subject],
      :body => params[:post][:body],
      :reply_post => reply_post
    )
    
    new_message_id = nil
    begin
      Net::NNTP.start(NEWS_SERVER) do |nntp|
        new_message_id = nntp.post(post_string)[1][/<.*?>/]
      end
    rescue
      form_error 'Error: ' + $!.message and return
    end
    
    begin
      Net::NNTP.start(NEWS_SERVER) do |nntp|
        post_newsgroups.each{ |n| Newsgroup.sync_group!(nntp, n.name, n.status) }
      end
    rescue
      @sync_error = "Your post was accepted by the news server, but an error occurred while attempting to sync the newsgroup it was posted to. This may be a transient issue: Wait a couple minutes and manually refresh the newsgroup, and you should see your post.\n\nThe exact error was: #{$!.message}"
    end
    
    @new_post = Post.find_by_message_id(new_message_id)
    if not @new_post
      @sync_error = "Your post was accepted by the news server, but doesn't appear to actually exist; it may have been held for moderation or silently discarded (though neither of these should ever happen on CSH news). Wait a couple minutes and manually refresh the newsgroup to make sure this isn't a glitch in WebNews."
    end
  end
  
  def destroy
    if @post.nil?
      form_error "The post you are trying to cancel doesn't exist; it may have already been canceled. Try manually refreshing the newsgroup." and return
    end
    
    if not @post.newsgroup.posting_allowed?
      form_error "The newsgroup containing the post you are trying to cancel is read-only. Posts in read-only newsgroups cannot be canceled." and return
    end
    
    if not @post.authored_by?(@current_user) and not @current_user.is_admin?
      form_error "You are not the author of this post; you cannot cancel it without admin privileges." and return
    end
    
    begin
      Net::NNTP.start(NEWS_SERVER) do |nntp|
        nntp.post(@post.build_cancel_message(@current_user, params[:reason]))
      end
    rescue
      form_error 'Error: ' + $!.message and return
    end
    
    begin
      Net::NNTP.start(NEWS_SERVER) do |nntp|
        @post.all_newsgroups.each{ |n| Newsgroup.sync_group!(nntp, n.name, n.status) }
        Newsgroup.sync_group!(nntp, 'control.cancel', 'n')
      end
    rescue
      @sync_error = "Your cancel was accepted by the news server, but an error occurred while attempting to sync the local post database. This may be a transient issue: Wait a couple minutes and manually refresh the newsgroup, and the post should be gone.\n\nThe exact error was: #{$!.message}"
    end
  end
  
  def destroy_confirm
    @admin_cancel = !@post.authored_by?(@current_user)
    render 'shared/dialog'
  end
  
  def edit_sticky
    render 'shared/dialog'
  end
  
  def update_sticky
    if not @current_user.is_admin?
      form_error "You cannot sticky or unsticky posts without admin privileges." and return
    end
    
    if @post.nil?
      form_error "The post you are trying to sticky doesn't exist; it may have been canceled. Try manually refreshing the newsgroup." and return
    end
    
    if params[:do_sticky]
      Chronic.time_class = Time.find_zone(@current_user.time_zone)
      t = Chronic.parse(params[:sticky_until])
      if t.nil?
        form_error "Unable to parse \"#{params[:sticky_until]}\"." and return
      end
      sticky_until = t - t.sec - ((((t.min + 15) % 30) - 15) * 1.minute)
      if sticky_until < Time.now
        form_error "You must enter a time that is in the future, when rounded to the nearest half-hour." and return
      end
      @post.in_all_newsgroups.each do |post|
        post.update_attributes(:sticky_user => @current_user, :sticky_until => sticky_until)
      end
    else
      if not @post.sticky_until.nil?
        @post.in_all_newsgroups.each do |post|
          post.update_attributes(:sticky_user => @current_user, :sticky_until => Time.now - 1.second)
        end
      end
    end
  end
  
  def update_star
    if @post.nil?
      @star_error = "The post you are trying to star/unstar doesn't exist; it may have been canceled. Try manually refreshing the newsgroup." and return
    end
    
    if @post.starred_by_user?(@current_user)
      @post.starred_post_entries.find_by_user_id(@current_user.id).destroy
      @starred = false
    else
      StarredPostEntry.create!(:user => @current_user, :post => @post)
      @starred = true
    end
  end
  
  private
    
    def set_list_layout_and_offset
      if params[:from_older] or params[:from_newer]
        @full_layout = false
        begin
          @from_older = Time.parse(params[:from_older]) if params[:from_older]
        rescue
          render :status => :bad_request, :json => json_error('datetime_invalid',
            "The from_older value '#{params[:from_older]}' could not be parsed as a datetime") and return
        end
        begin
          @from_newer = Time.parse(params[:from_newer]) if params[:from_newer]
        rescue
          render :status => :bad_request, :json => json_error('datetime_invalid',
            "The from_newer value '#{params[:from_newer]}' could not be parsed as a datetime") and return
        end
      else
        @full_layout = true
      end
    end
    
    def set_limit_from_params
      if params[:limit]
        begin
          @limit = Integer(params[:limit])
          if not @limit.between?(0, INDEX_MAX_LIMIT)
            @limit = [[0, @limit].max, INDEX_MAX_LIMIT].min
            render :status => :bad_request, :json => json_error('limit_outside_range',
              "The limit value '#{@limit}' is outside the acceptable range (0..#{INDEX_MAX_LIMIT})") and return
          end
        rescue
          render :status => :bad_request, :json => json_error('limit_invalid',
            "The limit value '#{params[:limit]}' could not be parsed as an integer'") and return
        end
      end
    end
    
    def build_search_conditions
      conditions = []
      values = []
      error = nil
      
      if not params[:keywords].blank?
        begin
          phrases = Shellwords.split(params[:keywords])
          keyword_conditions = []
          keyword_values = []
          exclude_conditions = []
          exclude_values = []
          
          phrases.each do |phrase|
            if phrase[0] == '-'
              exclude_conditions << '('
              exclude_conditions[-1] += 'subject like ?'
              exclude_values << '%' + phrase[1..-1] + '%'
              if not params[:subject_only]
                exclude_conditions[-1] += ' or body like ?'
                exclude_values << '%' + phrase[1..-1] + '%'
              end
              exclude_conditions[-1] += ')'
            else
              keyword_conditions << '('
              keyword_conditions[-1] += 'subject like ?'
              keyword_values << '%' + phrase + '%'
              if not params[:subject_only]
                keyword_conditions[-1] += ' or body like ?'
                keyword_values << '%' + phrase + '%'
              end
              keyword_conditions[-1] += ')'
            end
          end
          
          conditions << '(' + 
            '(' + keyword_conditions.join(' and ') + ')' + (
              exclude_conditions.empty? ?
                '' : ' and not (' + exclude_conditions.join(' or ') + ')'
            ) + ')'
          values += keyword_values + exclude_values
        rescue
          error = {
            :form_text => 'The keywords field has unbalanced quotes.',
            :json_id => 'keywords_invalid',
            :json_details => 'The keywords value contains unbalanced quotes'
          }
        end
      end
      
      if not params[:authors].blank?
        authors = params[:authors].split(',')
        conditions << '(' + (['author like ?'] * authors.size).join(' or ') + ')'
        authors.each do |author|
          values << '%' + author + '%'
        end
      end
      
      if not params[:date_from].blank?
        date_from = params[:date_from]
        date_from = 'January 1, ' + date_from if date_from[/^\d{4}$/]
        date_from = Chronic.parse(date_from)
        if not date_from
          error = {
            :form_text => "Unable to parse \"#{params[:date_from]}\" as a date.",
            :json_id => 'date_from_invalid',
            :json_details => "The date_from value '#{params[:date_from]}' could not be parsed as a datetime"
          }
        else
          conditions << 'date >= ?'
          values << date_from
        end
      end
      if not params[:date_to].blank?
        date_to = params[:date_to]
        date_to = 'January 1, ' + (date_to.to_i + 1).to_s if date_to[/^\d{4}$/]
        date_to = Chronic.parse(date_to)
        if not date_to
          error = {
            :form_text => "Unable to parse \"#{params[:date_to]}\" as a date.",
            :json_id => 'date_to_invalid',
            :json_details => "The date_to value '#{params[:date_to]}' could not be parsed as a datetime"
          }
        else
          conditions << 'date <= ?'
          values << date_to
        end
      end
      
      return conditions, values, error
    end
end
