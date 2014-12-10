require 'rubygems'
require 'koala'
require 'active_record'
require 'vine'
require 'net/smtp'

ActiveRecord::Base.establish_connection(
    :adapter => "mysql2",
    :host => '',
    :database => 'facebook_billing',
    #connect using username and password
    :username => '',
    :password => '',
)

recipients = ""  #who gets emailed on new invoices
mailuser = ''  #where the emails originate from
mailsmtp = ''  #smtp server ip address

appid = ""  #facebook Open Graph APP ID
appsecret = ""  #facebook Open Graph seceret

class AddSystemSettings < ActiveRecord::Migration
  if !ActiveRecord::Schema.tables.include?("clients")
    create_table :clients do |t|
      t.string :account_id
      t.string :name
      t.integer :account_status
      t.string :balance
    end
  end

  if !ActiveRecord::Schema.tables.include?("transactions")
    create_table :transactions do |t|
      t.string :account_id
      t.string :transaction_id
      t.string :status
      t.string :time
      t.string :total_amount
      t.string :app_amount
      t.string :charge_type
      t.string :billing_start_time
      t.string :billing_end_time
      t.string :payment_option
      t.string :provider_amount
      t.string :tx_type
    end
  end
  if !ActiveRecord::Schema.tables.include?("tokens")
     create_table :tokens do |t|
       t.string :tokenname
       t.string :tokenid
      end
  end
end

class Clients < ActiveRecord::Base
end

class Transactions < ActiveRecord::Base
end

class Tokens < ActiveRecord::Base
end


#create new long term token every run
tokenhash = Tokens.find_by tokenname: "token"
oauth = Koala::Facebook::OAuth.new(appid, appsecret)
new_access_info = oauth.exchange_access_token_info tokenhash[:tokenid]
finaltoken = new_access_info["access_token"]
Tokens.destroy_all("tokenname = 'token'")
Tokens.create(:tokenname => 'token', :tokenid => finaltoken)
@graph = Koala::Facebook::API.new("#{finaltoken}")
customer_data = @graph.get_connections("v2.2", "me/adaccounts?fields=name,account_status,balance")

i = 0
account_ids = []
customer_data.each do |eachrecord|
  eachrecord.each do |capture_hash, value|
    if capture_hash == 'account_id'
      account_ids[i] = value
      i += 1
    end
  end
end
i = 0
eval_transactions = []
account_ids.each do |findcharges|
  eval_transactions[i] = @graph.get_connections("v2.2", "act_#{findcharges}/transactions")
  eval_transactions[i].each do |each_transaction|
  if !Transactions.exists?(transaction_id: each_transaction['id'])
      if !Clients.exists?(account_id: customer_data[i]['account_id'])
        Clients.create(:name => customer_data[i]['name'], :account_status => customer_data[i]['account_status'], :balance => customer_data[i]['balance'], :account_id => customer_data[i]['account_id'], :id => customer_data[i]['id'])
      end
      account = Clients.find_by account_id: "#{customer_data[i]['account_id']}"

    if account[:name] == ''
        Net::SMTP.start(mailsmtp, 25) do |smtp|
          message = ''
          message = <<EOF
From: Admin <#{mailuser}>
To: #{recipients}
Subject: Transaction Posted but name is empty

     Customer Name:
     Transaction ID: #{each_transaction['id']}
     Transaction Time: #{each_transaction['time']}
     Customer Account ID: #{customer_data[i]['account_id']}
     App Amount: #{each_transaction.access('app_amount.amount')}
     Total Amount: #{each_transaction.access('amount.total_amount')}
     Charge Type: #{each_transaction['charge_type']}
     Billing Start Time: #{each_transaction['billing_start_time']}
     Billing End Time: #{each_transaction['billing_end_time']}
     Payment Option: #{each_transaction['payment_option']}
     Provider Amount: #{each_transaction.access('provider_amount.amount')}
     Tx Type: #{each_transaction['tx_type']}
EOF
          smtp.send_message(message, mailuser, recipients)
        end
      else
        Net::SMTP.start(mailsmtp, 25) do |smtp|
          message = ''
          message = <<EOF
From: Admin <#{mailuser}>
To: #{recipients}
Subject: Customer #{account[:name]} Transaction #{each_transaction['id']} Posted

     Customer Name: #{account[:name]}
     Transaction ID: #{each_transaction['id']}
     Transaction Time: #{each_transaction['time']}
     Customer Account ID: #{customer_data[i]['account_id']}
     App Amount: #{each_transaction.access('app_amount.amount')}
     Total Amount: #{each_transaction.access('amount.total_amount')}
     Charge Type: #{each_transaction['charge_type']}
     Billing Start Time: #{each_transaction['billing_start_time']}
     Billing End Time: #{each_transaction['billing_end_time']}
     Payment Option: #{each_transaction['payment_option']}
     Provider Amount: #{each_transaction.access('provider_amount.amount')}
     Tx Type: #{each_transaction['tx_type']}
EOF
          smtp.send_message(message, mailuser, recipients)
        end
      end
      Transactions.create(:transaction_id => each_transaction['id'], :status => each_transaction['status'], :time => each_transaction['time'], :account_id => customer_data[i]['account_id'], :app_amount => each_transaction.access('app_amount.amount'), :total_amount => each_transaction.access('amount.total_amount'), :charge_type => each_transaction['charge_type'], :billing_start_time => each_transaction['billing_start_time'], :billing_end_time => each_transaction['billing_end_time'], :payment_option => each_transaction['payment_option'], :provider_amount => each_transaction.access('provider_amount.amount'), :tx_type => each_transaction['tx_type'])
    end
  end
  if !Clients.exists?(account_id: customer_data[i]['account_id'])
    Clients.create(:name => customer_data[i]['name'], :account_status => customer_data[i]['account_status'], :balance => customer_data[i]['balance'], :account_id => customer_data[i]['account_id'], :id => customer_data[i]['id'])
  end
  i += 1
end

