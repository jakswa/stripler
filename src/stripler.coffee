# Description:
#   Tip someone stellars with hubot.
#
# Dependencies:
#   None
#
# Configuration:
#   None
#
# Commands:
#   <name>+++ - tip a person in stellars
#   hubot show my info - show your stripler info
#   hubot set my stellar account to <id> - set your stellar account id (for stripler)
#
# Author:
#   jakswa <jakswa@gmail.com>

Remote = require('stellar-lib').Remote
Amount = require('stellar-lib').Amount

account_id = process.env.STRIPLER_ACCOUNT_ID
account_secret = process.env.STRIPLER_ACCOUNT_SECRET
tip_amount = 1
last_tipped = null
rate_limit = 60 * 1000 # 60s

default_server =
  host: 'live.stellar.org'
  port: 9001
  secure: true
servers = [default_server]

remote = new Remote(
  trusted: true
  #trace: true
  servers: servers
  local_fee: true
)

module.exports = (robot) ->
  userInfo = (user, key, value) ->
    info = robot.brain.get("stripler::#{user}") or {}
    if value and key
      info[key] = value
      robot.brain.set("stripler::#{user}", info)
      return value
    else if key
      return info[key]
    else
      return info

  robot.respond /show my info/, (msg) ->
    user = msg.message.user.name
    account = userInfo(user)
    msg.reply "Your info: #{JSON.stringify(account)}"

  register_account_cmd = "set my stellar account to"
  robot.respond new RegExp("#{register_account_cmd} ([^ ]+)"), (msg) ->
    user = msg.message.user.name
    userInfo(user, 'account_id', msg.match[1])
    owed = parseInt(userInfo(user, 'owed'), 10)
    if owed
      userInfo(user, 'owed', 0)
      msg.reply "Thanks! Sending you #{owed}STR right now!"
      tip_account targetUser, owed, (resp, err) ->
        if err
          msg.reply "error: #{err.error_message}"
        else
          msg.reply "Done! Check your account"
    else
      msg.reply "Ok. I'll tip you (#{user}) at the address: #{msg.match[1]}"

  robot.hear /^([^ ]+)\+\+\+/, (msg) ->
    time_diff = (new Date() - last_tipped)
    if time_diff < rate_limit
      time_left = (rate_limit - time_diff) / 1000
      msg.reply "Slow down! You can only tip every #{rate_limit / 1000} seconds. Try again in #{time_left}s."
      return
    targetUser = msg.match[1]
    sendingUser = msg.message.user.name
    if targetUser == sendingUser
      msg.reply "You can't tip yourself, silly."
      return
    unless userInfo(targetUser, 'account_id')
      owed = userInfo(targetUser, 'owed') or 0
      owed = userInfo(targetUser, 'owed', owed+tip_amount)
      msg.send "#{targetUser} will receive #{owed}STR when they PM me saying, '#{register_account_cmd} <account_id>'"
      return
    tip_account targetUser, (resp, err) ->
      if err
        msg.reply "error: #{err.error_message}"
      else
        msg.send "#{targetUser} is on the rise! #{tip_amount}STR is on the way"

check_account = (id, cb) ->
  remote.connect ->
    request = remote.requestAccountInfo(id)
    request.callback (err, resp) ->
      cb resp, err
      remote.disconnect()
    request.request()

default_amt = Amount.from_human(tip_amount + "STR")
tip_account = (id, amt, cb) ->
  if not cb and amt
    cb = amt
    amt = null
  remote.set_secret(account_id, account_secret)
  remote.connect ->
    transaction = remote.transaction()
    transaction.payment(
      from: account_id
      to: id
      amount: amt or default_amt
    )
    transaction.on 'error', cb
    transaction.on 'success', cb
    transaction.submit()
