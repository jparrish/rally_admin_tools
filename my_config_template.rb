# Using the module only as a namespace - hence the "self." prefix to defs.
module MyConfig
  def self.credentials
    {username: 'name@company.com',
     password: 'foo'}
  end

  def self.domain
    # Default domain appended to user id if the id has no domain.
    'company.com'
  end

  def self.debug_email
    # Email address to associate with new user for debugging purposes. Used if
    # "override_email" (below) returns true.
    'name@company.com'
  end

  def self.override_email
    false
  end
end
