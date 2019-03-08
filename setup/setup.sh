#!/bin/bash

# Generate a random number for unique resource names
declare instanceId=$(($RANDOM * $RANDOM))

# Variables
declare gitUrl=https://github.com/MicrosoftDocs/mslearn-aspnet-core
declare gitBranch=persist-data-ef-core
declare srcWorkingDirectory=~/mslearn-aspnet-core/src
declare gitRepoWorkingDirectory=$srcWorkingDirectory/ContosoPets.Api

declare sqlServerName=sql$instanceId
declare sqlHostName=$sqlServerName.database.windows.net
declare sqlUsername=SqlUser
declare sqlPassword=Pass.$RANDOM
declare databaseName=ContosoPets
declare sqlConnectionString="Data Source=$sqlServerName.database.windows.net;Initial Catalog=$databaseName;Connect Timeout=30;Encrypt=True;TrustServerCertificate=False;ApplicationIntent=ReadWrite;MultiSubnetFailover=False"
declare keyVaultName=vault$instanceId
declare keyVaultEndpoint=https://$keyVaultName.vault.azure.net/
declare resourceGroupName=EfCoreModule

declare websiteName=web$instanceId
declare webAppUrl=https://$websiteName.azurewebsites.net
declare webAppDeploymentPassword=0iQzB97IEc

declare connectFile='connect.txt'

# Functions
setAzureCliDefaults() {
    echo "Setting default Azure CLI values..."

    az configure --defaults \
        group=$resourceGroupName \
        location=SouthCentralUs \
        web=$websiteName
}
resetAzureCliDefaults() {
    echo "Resetting default Azure CLI values..."
    az configure --defaults \
        group= \
        location= \
        web=
}

initEnvironment(){
    # Set location
    cd ~

    # Display installed .NET Core SDK version
    dotnetsdkversion=$(dotnet --version)
    echo "Using .NET Core SDK version $dotnetsdkversion"

    # Install .NET Core global tool to display connection info
    dotnet tool install dotnetsay --tool-path ~/dotnetsay

    # Greetings!
    ~/dotnetsay/dotnetsay $'\n\033[1;37mHi there!\n\033[0;37mI\'m going to setup some \033[1;34mAzure\033[0;37m resources\nand get the code you\'ll need for this module.\033[1;35m'
    echo $'\033[0;37m'

    echo "Deployment tasks run asynchronously from here on."
}

downloadAndBuild() {
    # Set location
    cd ~

    # Set global Git config variables
    git config --global user.name "Microsoft Learn Student"
    git config --global user.email learn@contoso.com
    
    # Download the sample project, restore NuGet packages, and build
    echo "Downloading code..."
    git clone --branch $gitBranch $gitUrl --quiet
    echo "Downloaded code!"

    echo "Building code..."
    cd $gitRepoWorkingDirectory
    dotnet build --verbosity quiet 
    echo $'\033[0;37mBuilt code!'
}

showResults() {
    connectInfo=$'\n'
    connectInfo+=$'\033[1;32m\033[4mConnection Info\033[0;37m (view again by running: \033[1;37mcat ~/connect.txt \033[0;37m)'
    connectInfo+=$'\n'

    # db connection
    connectInfo+=$'\033[1;35mDB Connection String:\033[0;37m '
    connectInfo+=$sqlConnectionString
    connectInfo+=$'\n' 
    # username 
    connectInfo+=$'\033[1;35mDB Hostname: \033[0;37m'
    connectInfo+=$sqlHostName
    connectInfo+=$'\n'
    # username 
    connectInfo+=$'\033[1;35mDB Username: \033[0;37m'
    connectInfo+=$sqlUsername@$sqlServerName 
    connectInfo+=$'\n'
    # password
    connectInfo+=$'\033[1;35mDB Password: \033[0;37m'
    connectInfo+=$sqlPassword
    connectInfo+=$'\n'
    # key vault
    connectInfo+=$'\033[1;35mKey Vault Endpoint: \033[0;37m'
    connectInfo+=$keyVaultEndpoint
    connectInfo+=$'\n'

    connectInfo+=$'\033[1;35mWeb App URL: \033[0;37m'
    connectInfo+=$webAppUrl
    connectInfo+=$'\n'

    # Set to purple for drawing .NET Bot
    connectInfo+=$'\033[1;35m'

    echo $'Done!\n\n'
    ~/dotnetsay/dotnetsay $'\n\033[1;37mYour environment is ready!\n\033[0;37mI set up some \033[1;34mAzure\033[0;37m resources and downloaded the code you\'ll need.\n\033[1;35mYou can find your connection information below.\033[1;35m'
    echo "$connectInfo" > ~/$connectFile
    cat ~/$connectFile
}

# Provision Azure Resource Group
provisionResourceGroup() {
    echo "Provisioning Azure Resource Group..."

    az group create \
        --name $resourceGroupName \
        --output none

    echo "Provisioned Azure Resource Group!"
}

# Provision Azure SQL Database
provisionDatabase() {
    echo "Provisioning Azure SQL Database..."

    az sql server create \
        --name $sqlServerName \
        --admin-user $sqlUsername \
        --admin-password $sqlPassword \
        --output none

    az sql db create \
        --name $databaseName \
        --server $sqlServerName \
        --output none

    az sql server firewall-rule create \
        --name AllowAzureAccess \
        --start-ip-address 0.0.0.0 \
        --end-ip-address 0.0.0.0 \
        --server $sqlServerName \
        --output none

    echo "Provisioned Azure SQL Database!"
}

# Provision Azure App Service
provisionAppService() {
    echo "Provisioning Azure App Service..."

    az appservice plan create \
        --name $websiteName \
        --output none

    az webapp create \
        --name $websiteName \
        --plan $websiteName \
        --output none
        
    # Enable Managed Service Identity on web app
    declare -g webAppPrincipalId=$(az webapp identity assign \
        --query principalId \
        --output tsv)

        # Create a deployment user
    az webapp deployment user set \
        --user-name $websiteName \
        --password $webAppDeploymentPassword \
        --output none
    
    # Set the deployment source
    az webapp deployment source config-local-git \
        --output none

    echo "Provisioned Azure App Service!"
}

# Set Git remote for pushing to Azure
setGitRemoteRepository() {
    echo "Setting up publishing to Azure..."
    # Add the URL as a Git remote repository
    cd $gitRepoWorkingDirectory
    git remote add azure https://$websiteName:$webAppDeploymentPassword@$websiteName.scm.azurewebsites.net/$websiteName.git
    echo "Publishing to Azure enabled!"
}

# Provision Azure Key Vault
provisionKeyVaultForWebApp() {
    echo "Provisioning Azure Key Vault..."

    az keyvault create \
        --name $keyVaultName \
        --output none
    
    # Set an access policy for the web app's principal ID
    # which permits Get & List operations on the Key Vault
    az keyvault set-policy \
        --name $keyVaultName \
        --object-id $webAppPrincipalId \
        --secret-permissions get list \
        --output none  

    echo "Provisioned Azure Key Vault!"
}

# Create resources
initEnvironment
downloadAndBuild &
buildTask=$!
setAzureCliDefaults
provisionResourceGroup
provisionDatabase &
(provisionAppService && provisionKeyVaultForWebApp) & 
wait &>/dev/null
resetAzureCliDefaults
setGitRemoteRepository
cd $srcWorkingDirectory
showResults
code .