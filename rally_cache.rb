require 'singleton'

# Class to help Logger output to both STOUT and to a file
class MultiIO
  def initialize(*targets)
    @targets = targets
  end

  def write(*args)
    @targets.each { |t| t.write(*args) }
  end

  def close
    @targets.each(&:close)
  end
end

#Cache of Rally users
class Users
  include Singleton
  include Enumerable

  def configure(config)
    @rally = config[:connection]
    @logger = config[:logger]
    @workspace_name = config[:workspace]
    @user_cache = {}
    @cache_filled = false
  end

  def find_user(name)
    fill_cache unless @cache_filled
    @user_cache[name]
  end

  def has_user?(name)
    fill_cache unless @cache_filled
    @user_cache.has_key? name
  end

  def update_cache(user)
    raise 'update_users called before cache filled' unless @cache_filled
    @user_cache[#noinspection RubyResolve
        user.UserName] = user
  end

  # Needed for Enumerable
  def each(&block)
    fill_cache unless @cache_filled
    @user_cache.each_value &block
  end

  # Needed for Enumerable
  def size
    fill_cache unless @cache_filled
    @user_cache.size # count of users in cache
  end

  private
  #noinspection RubyResolve
  def fill_cache
    start = Time.new
    results = @rally.find do |query|
      query.type = :user
      query.fetch = 'UserName,FirstName,LastName,DisplayName,UserPermissions,name,Role,Project'
      query.page_size = 200 #optional - default is 200
      query.limit = 50000 #optional - default is 99999
      query.order = 'UserName Asc'
    end
    @logger.info "Time to load users for cache: #{Time.new - start} sec."

    results.each do |user|
      if user.UserPermissions != nil
        @logger.debug "User, \"#{user.UserName}\", has: #{user.UserPermissions.length} permissions."
      else
        @logger.warn "User, \"#{user.UserName}\", has no permissions."
      end

      if @user_cache.has_key? user.UserName
        @logger.warn "Duplicate user, \"u.UserName\""
      else
        @user_cache[user.UserName] = user
      end
    end
    @cache_filled = true
  end
end

class Workspace
  attr_accessor :projects
  attr_reader :name, :_ref

  def initialize(workspace)
    @name = workspace.name
    @_ref = workspace._ref
    @projects = nil
  end
end

# Cache of Rally workspaces and their associated projects
class Workspaces
  include Singleton
  include Enumerable

  def configure(config)
    @rally = config[:connection]
    @logger = config[:logger]
    @workspace_name = config[:workspace]
    @workspace_cache = {}
    @cache_filled = false
  end

  def find_workspace(name)
    fill_cache unless @cache_filled
    @workspace_cache[name]
  end

  def each(&block)
    fill_cache unless @cache_filled
    @workspace_cache.each_value &block
  end

  private
  def fill_projects(workspace)
    start = Time.new
    results = @rally.find do |query|
      query.type = :project
      #noinspection RubyStringKeysInHashInspection
      query.workspace = {'_ref' => "#{workspace._ref}"}
      query.fetch = 'Name,State,Editors,TeamMembers'
      query.order = 'Name Asc'
    end
    @logger.info "Time to load #{workspace.name}\'s projects for cache: #{Time.new - start} sec."

    # Can't create a hash keyed on name because project names aren't unique.
    workspace.projects = results
  end

  def fill_cache
    start = Time.new
    results = @rally.find do |query|
      query.type = :subscription
      query.fetch = 'Name,Workspaces'
      query.order = 'Name Asc'
    end
    @logger.info "Time to load workspaces for cache: #{Time.new - start} sec."

    results.each do |subscription|
      if subscription.Workspaces != nil
        @logger.info "Subscription, \"#{subscription.name}\", has: #{subscription.Workspaces.length} workspaces."

        subscription.Workspaces.each do |rally_workspace|
          if @workspace_name.nil? or (@workspace_name == rally_workspace.name)
            if @workspace_cache.has_key? rally_workspace.name
              @logger.error "Duplicate workspace, \"#{rally_workspace.name}\""
            elsif rally_workspace.State == 'Closed'
              @logger.warn "Workspace, \"#{rally_workspace.name}\", is closed."
            else
              workspace = Workspace.new(rally_workspace)
              fill_projects(workspace)
              @workspace_cache[rally_workspace.name] = workspace
            end
          end
        end
      else
        @logger.warn "Subscription, \"#{subscription.name}\", has no workspaces."
      end
    end
    @cache_filled = true
  end
end

class RallyCache
  def self.configure(config)
    Workspaces.instance.configure(config)
    Users.instance.configure(config)
  end
end