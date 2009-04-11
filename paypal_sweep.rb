#!/usr/bin/env ruby
#
# == PayPal Sweep
#   This script automates the withdrawal of the balance of a specified Paypal
#   account to the users bank account.
#
# == Usage 
#   See README for usage.
#
# == Author
#   Jeremy Jarvis
#   http://twitter.com/jeremyjarvis
# 
# == Copyright
#   Copyright (c) 2009 Jeremy Jarvis. Licensed under the MIT License:
#   http://www.opensource.org/licenses/mit-license.php

require 'rubygems'
require 'optiflag'
require 'date'
require 'nokogiri'
require 'mechanize'
require 'logger'

class PaypalSweep
  # Set the page urls - these seem more stable than using Mechanize to click links
  LOGIN_URL = 'https://www.paypal.com/uk/cgi-bin/webscr?cmd=_login-run'
  LOGOUT_URL = 'https://www.paypal.com/uk/cgi-bin/webscr?cmd=_logout'
  OVERVIEW_URL = 'https://www.paypal.com/uk/cgi-bin/webscr?cmd=_account'
  WITHDRAWAL_URL = 'https://www.paypal.com/uk/cgi-bin/webscr?cmd=_withdraw-funds-bank&nav=0.2.0'
  
  def initialize
    # start logger
    @log = Logger.new('log/paypal-sweep.log','weekly')
    @log.level = Logger::DEBUG
    
    # Create new mechanize object
    WWW::Mechanize.html_parser = Nokogiri::HTML
    @agent = WWW::Mechanize.new

    @agent.user_agent_alias = 'Mac Safari' # make it look like a normal browser
    @agent.keep_alive = false # this prevents some errors with SSL
    @agent.follow_meta_refresh = true

    # TO DO - add additional defaults
    @user = false
    @password = false
    @sweep_mode = false
    # @log_dir = false
  end

  # Process arguments, then do the stuffs
  def run
    process_arguments
    output_message display_mode
    
    if login_to_paypal?
      if @sweep_mode
        do_withdrawal(current_balance)
      else
        current_balance
      end
      logout_of_paypal
    end
  end
  
  protected
  
  # Setup the vars
  def process_arguments
    @user = ARGV.flags.user
    @password = ARGV.flags.password
    @sweep_mode = true if ARGV.flags.sweep?
  end
    
  def output_message content
    # TO DO: output to log if option set
    puts content
    @log.info(content)
  end

  def login_to_paypal?
    output_message "Attempting login to Paypal account (#{@user})..."

    # Login to paypal account
    page = @agent.get(LOGIN_URL)
    page.form_with(:name => 'login_form') do |f|
      f.login_email  = @user
      f.login_password = @password
    end.click_button
    
    # Hack: doesn't redirect properly after login
    page = @agent.get(OVERVIEW_URL)

    if h1_for(page) == 'My Account Overview'
      output_message "Login successful.\n\n"
      return true
    else
      output_message "Login failed."
      return false
    end
  end

  def logout_of_paypal
    output_message "Logging out of Paypal..."
    @agent.get(LOGOUT_URL)
    
    # TODO: check the logout was actually successful
    output_message "Logged out.\n\n"
  end

  def h1_for page
    h1 = page.search('td.heading h1').inner_text.strip
    return h1
  end
  
  def headline_for page
    headline = page.search('div#headline h2').inner_text.strip
    return headline
  end
  
  def display_mode
    if @sweep_mode
      return "[Mode] Balance and Sweep"
    else
      return "[Mode] Balance only"
    end
  end

  def error_message_for page
    error_msg = page.search('div.messageBox.error p').inner_text.strip
    return error_msg
  end

  def current_balance
    output_message "Retrieving account balance..."
    
    begin
      # Open bank withdrawal page
      page = @agent.get(WITHDRAWAL_URL)
    
      if headline_for(page) == 'Withdraw Funds by Electronic Transfer'
         # scrape the balance amount 
         balance_text = page.search("/html/body/div/div[3]/div[3]/div/form/p[3]/span[2]").inner_text
       
         # TODO: make this a regex
         balance_text.gsub!('GBP','')
         balance_text.gsub!('£','')
         balance_text.gsub!(',','')
       
         balance_amt = balance_text.to_f
       
         # make sure amount has two decimal places
         balance_amt = sprintf("%.2f", balance_text)
       
         output_message "Balance: £#{balance_amt} (at #{DateTime.now.strftime("%I:%M:%S%P %a %d %b %Y")}) \n\n"
       
         return balance_amt
      else
        output_message "Unable to retrieve balance."
        return false
      end
    rescue
      output_message "Error attempting to retrieve balance."
      return false
    end
  end
  
  def do_withdrawal(amount)
    # open the withdrawal page
    page = @agent.get(WITHDRAWAL_URL)
    
    # Start withdrawal  
    withdraw_form = page.form_with(:name => 'WithDrawForm')
    withdraw_form.amount = amount
    review_page = @agent.submit(withdraw_form)

    if headline_for(review_page) == 'Review Withdraw Funds'
      conf_page = @agent.submit(review_page.forms[1], review_page.forms[1].buttons.first) # click submit button
      
      #review_form = review_page.forms.first
      #conf_page = @agent.submit(review_form, review_form.button_with(:name => 'submit.x')) # click submit button

      if headline_for(conf_page) == 'Your electronic funds transfer request is in process'
         output_message "Transfer success: #{headline_for conf_page}\n\n"  
         return true
      else
         output_message "Transfer unconfirmed: #{headline_for conf_page}"
         return false
      end

    else
      output_message "Transfer Failed: #{error_message_for review_page}"
      return false
    end

  end

end

module Example extend OptiFlagSet
  # TODO: optional_flag "log"
  # optional_flag "quiet"

  extended_help_flag "info","i"
  
  flag "user" do 
      alternate_forms "u"
      description "The Paypal user name/email"
  end
  
  flag "password" do 
      alternate_forms "p"
      description "The password for your Paypal account"
  end
  
  optional_switch_flag "sweep" do
      alternate_forms "s"
      description "Sweep mode: setting this flag will actually complete the sweep, otherwise only the balance will be output."
  end
    
  and_process!
end

# Create and run the app
app = PaypalSweep.new
app.run
