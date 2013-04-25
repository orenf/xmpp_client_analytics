# What does this thing do?

This ruby application offers Call Analytics. You need to be an OnSIP user, and you need ruby running on your system.  The data will be stored in your environment.

# XmppClientAnalytics

This is a fairly alpha product. It runs fine, but doesn't survive a network drop.

# Requires the following gems

xmpp4r
mysql
daemons

## Usage

1. Go into lib/xmpp_client_analytics/active_calls/xmpp_client.yaml, and configure the app.
2. Set your mysql user
3. Create your users in admin.onsip.com
4. Register phones for these users
3. Add the AOR / SIP Address of these users. The password is the OnSIP Web Password. Find it @ http://my.onsip.com, click "I forgot my password".

## Run

./lib/xmpp_client_analytics.rb
