# encoding: UTF-8

# Usage: ruby summary.rb [<workspace name>]
# Expected input files are defined as global variables below

# Delimited list of all projects in Workspace
# $project_cache_filename  = 'project_summary.txt'

#include for rally json library gem
require 'rally_api'
require 'csv'
require 'logger'
require File.dirname(__FILE__) + '/rally_cache.rb'
require File.dirname(__FILE__) + '/my_config.rb'

# constants
USAGE = 'usage: ruby summary.rb [<workspace name>]'

# Field delimiter for permissions file
DELIM = ','

$logger = nil

def strip_role_from_permission(str)
  # Removes the role from the Workspace,ProjectPermission String so we're left with just the
  # Workspace/Project Name
  str.gsub(/\bAdmin|\bUser|\bEditor|\bViewer/, '').strip
end

#noinspection RubyResolve
def list_users( verbose = false )
  print "There are #{Users.instance.size} users.\n"

  # loop through all users and output permissions summary
  Users.instance.each do |user|
    if verbose
      if user.UserPermissions != nil
        $logger.info "User, \"#{user.UserName}\", has: #{user.UserPermissions.length} permissions."
        user.UserPermissions.each do |this_permission|
          print "#{user.UserName}#{DELIM}"
          print "#{user.FirstName}#{DELIM}"
          print "#{user.LastName}#{DELIM}"
          print "#{user.DisplayName}#{DELIM}"
          name = strip_role_from_permission(this_permission.name)
          print "#{name}#{DELIM}"
          print "#{this_permission._type}#{DELIM}"
          print "#{this_permission.Role}"
          print "\n"
        end
      else
        $logger.info "User, \"#{user.UserName}\", has no permissions."
        print "#{user.UserName}#{DELIM}"
        print "#{user.FirstName}#{DELIM}"
        print "#{user.LastName}#{DELIM}"
        print "#{user.DisplayName}#{DELIM}"
        print "N/A#{DELIM}"
        print "N/A#{DELIM}"
        print 'N/A'
        print "\n"
      end
    else
      permission_count = user.UserPermissions ? user.UserPermissions.length : 0
      print "User, \"#{user.UserName}\", has: #{permission_count} permissions.\n"
    end
  end
end

def list_workspaces
  Workspaces.instance.each do |workspace|
    puts "Workspace \"#{workspace.name}\": #{workspace._ref}"
  end
  puts "\r\r"
end

def list_projects
  Workspaces.instance.each do |workspace|
    projects = workspace.projects
    if projects.nil?
      $logger.info "Workspace, \"#{workspace}\", has no projects."
    else
      $logger.info "Workspace, \"#{workspace.name}\", has: #{projects.length} projects."

      print "Workspace#{DELIM}"
      print "Name#{DELIM}"
      print "State#{DELIM}"
      print '_ref'
      print "\n"
      projects.each do |project|
        $logger.info "Listing Project:  #{project.name}."
        print "#{workspace.name}#{DELIM}"
        print "#{project.name}#{DELIM}"
        print "#{project.State}#{DELIM}"
        print "#{project._ref}"
        print "\n"
      end
    end
  end
  puts "\r\r"
end

def create_connection
  #Setting custom headers
  headers = RallyAPI::CustomHttpHeader.new
  headers.name = 'Ruby Rally Summary Tool: JSON'
  headers.vendor = 'Yahoo!'
  headers.version = '0.10'

  config = {headers: headers,
            version: '1.40',
            base_url: 'https://rally1.rallydev.com/slm'}

  workspace = ARGV[0]
  if workspace != nil
    config[:workspace] = workspace
    $logger.info "Connecting to Rally workspace \"#{workspace}\"..."
  else
    $logger.info 'Connecting to the Rally default workspace...'
  end

  RallyAPI::RallyRestJson.new(config.merge MyConfig::credentials)
end

begin
  log_file = File.open('summary.log', 'w+')
  #$logger = Logger.new MultiIO.new(STDOUT, log_file)
  $logger = Logger.new(log_file)
  $logger.level = Logger::INFO #DEBUG | INFO | WARNING | FATAL

  rally = create_connection
  RallyCache.configure({connection: rally, logger: $logger, workspace: ARGV[0]})

  #list_workspaces
  #list_projects
  list_users
  log_file.close

rescue => ex
  $logger.error ex
  $logger.error ex.backtrace
end
