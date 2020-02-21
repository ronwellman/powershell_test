param ($ComputerName, $DomainFqdn, $DomainNetBIOS, $Password, $DomainAdminUser, $DomainAdminUserDisplayName, $DNSClientInterfaceAlias, $DNSIP, $DnsForwarderIPs)

Start-Transcript c:\ConfigurationLog.txt

Write-Output 'Creating ConfigData'
$ConfigData = @{
    AllNodes = @(@{
        NodeName = 'localhost'
        MachineName = $ComputerName
        DomainFqdn = $DomainFqdn
        DomainNetbios = $DomainNetBIOS
        Password = $Password
        DomainAdminUser = $DomainAdminUser
        DomainAdminUserDisplayName = $DomainAdminUserDisplayName
        DNSClientInterfaceAlias = $DNSClientInterfaceAlias
        DNSIP = $DNSIP
        DnsForwarders = $DnsForwarderIPs
        # DO NOT USE the below in production. Lab only!
        PsDscAllowPlainTextPassword = $true
        PSDscAllowDomainUser = $true
    })
}

$localCredential = New-Object System.Management.Automation.PSCredential(
            'Administrator', (ConvertTo-SecureString $Password -AsplainText -Force))



Write-Output 'Defining Configuration'
Configuration DC {
    
    Import-Module xComputerManagement, xNetworking, xDNSServer, xActiveDirectory, xAdcsDeployment
    Import-DscResource -ModuleName PSDesiredStateConfiguration
    Import-DscResource -ModuleName xComputerManagement -Name xComputer
    Import-DSCResource -ModuleName xNetworking -Name xDnsServerAddress
    Import-DSCResource -ModuleName xDNSServer -Name xDnsServerForwarder
    Import-DSCResource -ModuleName xDNSServer -Name xDnsRecord
    Import-DscResource -ModuleName xDNSServer -Name xDnsServerPrimaryZone
    Import-DSCResource -ModuleName xActiveDirectory -Name xADDomain
    Import-DSCResource -ModuleName xActiveDirectory -Name xADUser
    Import-DSCResource -ModuleName xActiveDirectory -Name xADGroup
    Import-DSCResource -ModuleName xAdcsDeployment -Name xAdcsWebEnrollment
    Import-DSCResource -ModuleName xAdcsDeployment -Name xAdcsCertificationAuthority

    Node $AllNodes.NodeName {
        LocalConfigurationManager {
            ActionAfterReboot = 'ContinueConfiguration'
            ConfigurationMode = 'ApplyAndAutoCorrect'
            RebootNodeIfNeeded = $true
        }

        $Credential = New-Object System.Management.Automation.PSCredential(
            '$($Node.DomainFqdn)\Administrator',
            (ConvertTo-SecureString $Node.Password -AsplainText -Force)
        )

        xComputer SetName {
            Name = $Node.MachineName
        }
        
        xDNSServerAddress SetDNS {
            Address = $Node.DNSIP
            InterfaceAlias = $Node.DNSClientInterfaceAlias
            AddressFamily = 'IPv4'
            DependsOn = '[WindowsFeature]DNS'
        }
        
        # Make sure AD DS is installed
        WindowsFeature ADDSInstall {
            Ensure = 'Present'
            Name   = 'AD-Domain-Services'
            DependsOn = '[WindowsFeature]DNS'
        }

        # # Make sure AD DS Tools are installed
        # WindowsFeature ADDSTools {
        #     Ensure = 'Present'
        #     Name   = 'RSAT-ADDS'
        # }

        WindowsFeature DNS {
            Ensure = 'Present'
            Name   = 'DNS'
            Credential = $localCredential
        }

        # # Create the Active Directory domain
        # xADDomain DC {
        #     DomainName = $node.DomainFqdn
        #     DomainNetbiosName = $node.DomainNetBIOS
        #     DomainAdministratorCredential = $Credential
        #     SafemodeAdministratorPassword = $Credential
        #     Credential = $Credential
        #     DependsOn = '[xComputer]SetName', '[WindowsFeature]ADDSInstall'
        # }

        # Configure DNS Forwarders on this server
        xDnsServerForwarder Forwarder {
            IsSingleInstance = 'Yes'
            IPAddresses = $node.DnsForwarders
            DependsOn = '[WindowsFeature]DNS'
        }

        # Create a Zone for the domain
        xDnsServerPrimaryZone primaryZone {
            Name = $node.DomainFqdn
            Ensure = 'Present'
            DependsOn = '[WindowsFeature]DNS'
        }

        # Create a DNS record for AD FS
        xDnsRecord dc {
            Name ='dc'
            Zone = $node.DomainFqdn
            Target = $Node.DNSIP
            Type = 'ARecord'
            Ensure = 'Present'
            DependsOn = '[WindowsFeature]DNS', '[xDnsServerPrimaryZone]primaryZone'
        }

        # # Ensure the AD CS role is installed
        # WindowsFeature ADCS-Cert-Authority {
        #     Ensure = 'Present'
        #     Name = 'ADCS-Cert-Authority'
        # }

        # # Ensure the AD CS RSAT is installed
        # WindowsFeature RSAT-ADCS {
        #     Ensure = 'Present'
        #     Name   = 'RSAT-ADCS'
        #     IncludeAllSubFeature = $true
        # }

        # # Ensure the AD CS web enrollment role feature is installed
        # WindowsFeature ADCS-Web-Enrollment {
        #     Ensure = 'Present'
        #     Name   = 'ADCS-Web-Enrollment'
        #     DependsOn = '[WindowsFeature]ADCS-Cert-Authority' 
        # }

        # # Ensure the IIS management console is installed for convenience
        # WindowsFeature Web-Mgmt-Console {
        #     Ensure = 'Present'
        #     Name   = 'Web-Mgmt-Console'
        # }

        # # Ensure the CA is configured
        # xAdcsCertificationAuthority CA {
        #     Ensure            = 'Present'        
        #     Credential        = $Credential
        #     CAType            = 'EnterpriseRootCA'
        #     CACommonName      = '$($node.DomainNetBIOS) Root CA'
        #     HashAlgorithmName = 'SHA256'
        #     DependsOn         = '[WindowsFeature]ADCS-Cert-Authority'
        # }

        # # Ensure web enrollment is configured
        # xAdcsWebEnrollment CertSrv {
        #     Ensure           = 'Present'
        #     IsSingleInstance = 'Yes'
        #     Credential       = $Credential
        #     DependsOn        = '[WindowsFeature]ADCS-Web-Enrollment','[xAdcsCertificationAuthority]CA' 
        # }

        # # Create a domain admin user for admin purposes
        # xADUser AdminUser {
        #     Ensure     = 'Present'
        #     DomainName = $node.DomainFqdn
        #     Username   = $node.DomainAdminUser
        #     Password   = $Credential
        #     DisplayName = $node.DomainAdminUserDisplayName
        #     DomainAdministratorCredential = $Credential
        #     DependsOn = '[xADDomain]DC'
        # }

        # # Put the domain admin user into the domain admins group (duh)
        # xADGroup DomainAdmins {
        #     Ensure = 'Present'
        #     GroupName = 'Domain Admins'
        #     GroupScope = 'Global'
        #     Category = 'Security'
        #     MembersToInclude = $node.DomainAdminUser
        #     Credential = $Credential
        #     DependsOn = '[xADUser]AdminUser'
        # }
        
        # xADGroup EnterpriseAdmins {
        #     Ensure = 'Present'
        #     GroupName = 'Enterprise Admins'
        #     GroupScope = 'Universal'
        #     Category = 'Security'
        #     MembersToInclude = $node.DomainAdminUser
        #     Credential = $Credential
        #     DependsOn = '[xAdUser]AdminUser'
        # }
    }
}

Write-Output 'Generating MOF'
DC -ConfigurationData $ConfigData

Write-Output 'Applying Configuration'
Start-DscConfiguration -Wait -Force -Path .\DC -Verbose -Credential $localCredential
