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
#   hubot how's the tip pool - show someone's raw balance (for stripler)
#   hubot set my stellar account to <id> - set your stellar account id (for stripler)
#
# Author:
#   jakswa <jakswa@gmail.com>

Promise = require('bluebird')

Remote = require('stellar-lib').Remote
Amount = require('stellar-lib').Amount

stripler_id = process.env.STRIPLER_ACCOUNT_ID
stripler_secret = process.env.STRIPLER_ACCOUNT_SECRET
tip_amount = 10
last_tipped = null
rate_limit = 30 * 1000 # 60s

default_server =
  host: 'live.stellar.org'
  port: 9001
  secure: true
servers = [default_server]

remote = new Remote(
  trusted: true
  #trace: true
  servers: servers
)
remoteConnect = new Promise (resolve, reject) ->
  remote.connect ->
    resolve()

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
      tip_account userInfo(user, 'account_id'), owed, (err, resp) ->
        if err
          msg.reply "error: #{err.error_message}"
        else
          msg.reply "Done! Check your account"
    else
      msg.reply "Ok. I'll tip you (#{user}) at the address: #{msg.match[1]}"

  robot.respond /how'?s the tip pool/, (msg) ->
    check_account stripler_id, (err, resp) ->
      if err
        msg.reply "error: #{err.error_message or err.message}"
        return

      balance = resp.account_data.Balance / 1000000
      str_bal = balance.toFixed(2)
      if balance < 100
        msg.reply "it's not looking good. There's only #{str_bal}STR left in the tipping pool."
      else if balance < 500
        msg.reply "things are doing okay. I have #{str_bal}STR left in the tipping pool."
      else
        msg.reply "we're on the up and up! I have #{str_bal}STR left in the tipping pool."

  robot.hear /^([^ ]+)\+\+\+/, (msg) ->
    targetUser = msg.match[1]
    sendingUser = msg.message.user.name
    if false#targetUser == sendingUser
      msg.reply "You can't tip yourself, silly."
      return
    time_diff = (new Date() - last_tipped)
    if time_diff < rate_limit
      time_left = Math.round((rate_limit - time_diff) / 1000)
      msg.reply "Slow down! You can only tip every #{rate_limit / 1000} seconds. Try again in #{time_left}s."
      return
    last_tipped = new Date()
    userDetails = userInfo(targetUser)
    unless userDetails.account_id
      owed = userDetails.owed or 0
      owed = userInfo(targetUser, 'owed', owed+tip_amount)
      msg.send "#{targetUser} will receive #{owed}STR when they PM me saying, '#{register_account_cmd} <long_and_ugly_account_id>'"
      return
    tot = userInfo(targetUser, 'cnt', (userDetails.cnt || 0) + tip_amount)
    tip_account userInfo(targetUser, 'account_id'), (err, resp) ->
      if err
        if err.result == 'tecUNFUNDED_PAYMENT'
          msg.reply "oops! I'm out of money. :( If anyone wants to revive me, send more to 'stripler' (#{stripler_id})."
        else
          msg.reply "oops: #{err.error_message or err.message}"
      else
        msg.send "#{targetUser} just rose #{tip_amount}STR! Score: #{tot}STR."

check_account = (id, cb) ->
  remoteConnect.then ->
    request = remote.requestAccountInfo(id)
    request.callback cb
    request.request()

default_amt = Amount.from_human(tip_amount + "STR")
tip_account = (address, amt, cb) ->
  if not cb and amt
    cb = amt
    amt = null
  amt = amt && Amount.from_human(amt + "STR")
  remoteConnect.then ->
    remote.set_secret(stripler_id, stripler_secret)
    transaction = remote.transaction()
    transaction.payment(
      from: stripler_id
      to: address
      amount: amt or default_amt
    )
    transaction.submit(cb)
