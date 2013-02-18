# encoding: UTF-8

#include for rally json library gem
require 'rally_api'
require 'csv'
require 'logger'
require File.dirname(__FILE__) + '/rally_cache.rb'
require File.dirname(__FILE__) + '/my_config.rb'

# constants
USAGE = 'usage: ruby add_users <csv user definitions file>'

ADMIN = 'Admin'
USER = 'User'
EDITOR = 'Editor'
VIEWER = 'Viewer'
NOACCESS = 'No Access'

# Field delimiter for user definition file
DELIM = ','

$logger = nil

# The format of the user definition file is:
# Header - ID sep FirstName sep LastName sep Workspace
# User1  - baz sep foo sep bar sep sandbox
# User2  - ......
# The ID field is used to construct the email address and rally user id
#TODO Downcase id to ensure a match if preexisting
def read_definitions
  definitions = []
  definitions_file = ARGV[0]
  $logger.info "Reading user definitions from \"#{definitions_file}\""
  options = {:col_sep => DELIM, :headers => :first_row, :return_headers => false}
  CSV.foreach(definitions_file, options) do |row|
    next if row.empty?
    id = row[0].strip
    first_name = row[1].strip
    last_name = row[2].strip
    workspace = row[3].strip
    definitions << {id: id, first_name: first_name, last_name: last_name, workspace: workspace}
  end
  definitions
end

def create_user(definition)
  new_user = nil

  #First make sure the user doesn't already have an account
  #TODO allow id to be in the form of an email address, in addition to just the prefix
  user_name = definition[:id].downcase + '@' + MyConfig::domain
  users = Users.instance
  if users.has_user? user_name
    $logger.warn "Account already exists for user #{user_name}"
  else
    new_user_obj = {}
    new_user_obj['UserName'] = user_name
    new_user_obj['EmailAddress'] = MyConfig::override_email ? MyConfig::debug_email : user_name
    new_user_obj['FirstName'] = definition[:first_name]
    new_user_obj['LastName'] = definition[:last_name]
    new_user_obj['DisplayName'] = definition[:first_name] + ' ' + definition[:last_name]

    #Can't create a user without explicitly specifying a workspace for some reason.
    new_user_obj['Workspace'] = Workspaces.instance.find_workspace(definition[:workspace])._ref

    begin
      #puts new_user_obj
      new_user = @rally.create(:user, new_user_obj)
      users.update_cache new_user #Update the cache so we can catch duplicates
      $logger.info "Created Rally user #{user_name}"
    rescue
      $logger.fatal "Error creating user: #{$!}"
      raise $!
    end
  end
  new_user
end

def create_project_permission(user, project, permission, workspace)
  new_permission_obj = {}
  new_permission_obj['Workspace'] = workspace._ref
  new_permission_obj['Project'] = project._ref
  new_permission_obj['User'] = user._ref
  new_permission_obj['Role'] = permission

  @rally.create(:projectpermission, new_permission_obj)
end

def add_project_permission(user, project, permission, workspace)
  if [USER, VIEWER, EDITOR, ADMIN].include? permission
    create_project_permission(user, project, permission, workspace)
    # You can't (unfortunately) just append a new permission to the existing ones
    #user.UserPermissions << create_project_permission(user, project, permission, workspace)
    $logger.debug "  #{#noinspection RubyResolve
    user.UserName} #{project.Name} - Permission set to #{permission}"
  else
    $logger.error "Invalid Permission - #{permission}"
  end
end

def update_permissions(user, definition)
  start = Time.new
  workspace = Workspaces.instance.find_workspace definition[:workspace]

  # Add Editor permissions for every project in the workspace
  workspace.projects.each do |project|
    add_project_permission(user, project, EDITOR, workspace)
  end
  $logger.info "\tUpdated #{#noinspection RubyResolve
  user.UserName}\'s permissions in #{Time.new - start} sec."
end

def create_connection
  #Setting custom headers
  headers = RallyAPI::CustomHttpHeader.new
  headers.name = 'Ruby Add User Tool: JSON'
  headers.vendor = 'Yahoo!'
  headers.version = '0.10'

  config = {headers: headers,
            version: '1.40',
            base_url: 'https://rally1.rallydev.com/slm'}

  $logger.info 'Connecting to Rally...'
  RallyAPI::RallyRestJson.new(config.merge(MyConfig::credentials))
end

begin
  if ARGV[0].nil?
    puts USAGE
    exit
  end

  log_file = File.open('add_users.log', 'w+')
  #$logger = Logger.new MultiIO.new(STDOUT, log_file)
  $logger = Logger.new(log_file)
  $logger.level = Logger::INFO #DEBUG | INFO | WARNING | ERROR | FATAL

  @rally = create_connection

  #Configure the cache
  RallyCache.configure({connection: @rally, logger: $logger})

  #Create an account for each user in the definition file
  #and assign editor permissions to all projects in the specified workspace
  definitions = read_definitions
  count = definitions.length
  start = Time.now
  definitions.each do |definition|
    user = create_user(definition)
    update_permissions(user, definition) unless user.nil?
  end
  $logger.info "\tProcessed #{count} users in #{Time.new - start} sec."
  log_file.close

rescue => ex
  $logger.error ex
  $logger.error ex.backtrace
end
