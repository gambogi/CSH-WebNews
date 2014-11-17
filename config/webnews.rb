# The name of the web server (for constructing URLs in emails)
SERVER_NAME = "webnews#{'-dev' unless Rails.env.production?}.csh.rit.edu"

# The local top-level domain for users of this installation
LOCAL_DOMAIN = 'csh.rit.edu'

# URL prefixes for the Profile and Wiki links
PROFILES_URL = 'https://members.csh.rit.edu/profiles/members/'
WIKI_URL = 'https://wiki.csh.rit.edu/wiki/'
WIKI_USER_URL = WIKI_URL + 'User:'

# Server variables that provide the user's username and display name
ENV_USERNAME = 'WEBAUTH_USER'
ENV_DISPLAY_NAME = 'WEBAUTH_LDAP_CN'

# Default time zone for new users, from `rake time:zones:all`
DEFAULT_TIME_ZONE = 'Eastern Time (US & Canada)'

# Date formats (SHORT is used in the dashboard feeds)
DATE_FORMAT = '%-m/%-d/%Y %-I:%M%P'
SHORT_DATE_FORMAT = '%-m/%-d %-I:%M%P'
DATE_ONLY_FORMAT = '%-m/%-d/%Y'
MONTH_ONLY_FORMAT = '%B %Y'

# Newsgroups whose names match this SIMILAR TO pattern are excluded from the
# activity feed and "all newsgroups" search
DEFAULT_NEWSGROUP_FILTER = 'control%|%.?test'

# Default and maximum values for the 'limit' parameter to Posts#index
INDEX_DEF_LIMIT_1 = 8  # Default limit when the request is only in one direction (older or newer)
INDEX_DEF_LIMIT_2 = 4  # Default limit when the request is for both directions (older and newer)
INDEX_MAX_LIMIT = 20   # Maximum limit that can be requested with the API
INDEX_RSS_LIMIT = 10   # Maximum limit for the built-in search RSS feed

# Default subscriptions that are copied to new users on creation
# (must include one newsgroup-less "default" setting with all options set)
NEW_USER_SUBSCRIPTIONS = [
  { unread_level: 0, email_level: 3, digest_type: 'none' },
  { newsgroup_name: 'control.cancel', unread_level: 3, email_level: 3, digest_type: 'none' },
  { newsgroup_name: 'csh.test', unread_level: 3, email_level: 3, digest_type: 'none' }
]

# Set true to disable authentication and auto-login as a test user with admin privileges
DEVELOPMENT_MODE = false
