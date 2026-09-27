namespace :crm do
  desc 'Provision the default CRM pipeline for every existing account'
  task provision_accounts: :environment do
    Account.find_each do |account|
      Crm::ProvisionAccount.call(account)
      puts "CRM provisioned for account #{account.id} - #{account.name}"
    end
  end
end
