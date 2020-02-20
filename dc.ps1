Configuration DC {

    Import-DscResource -ModuleName xComputerManagement -Name xComputer
    Import-DSCResource -ModuleName xDNSServer -Name xDnsServerAddress
    Import-DSCResource -ModuleName xDNSServer -Name xDnsRecord
    Import-DSCResource -ModuleName xActiveDirectory -Name xADDomain
    Import-DSCResource -ModuleName xActiveDirectory -Name xADUser
    Import-DSCResource -ModuleName xActiveDirectory -Name xADGroup
    Import-DSCResource -ModuleName xAdcsDeployment -Name xAdcsCertificationAuthority

    Node $AllNodes.NodeName {
        LocalConfigurationManager {
            ActionAfterReboot = "ContinueConfiguration"
            ConfigurationMode = "ApplyAndAutoCorrect"
            RebootNodeIfNeeded = $true
        }

        $Credential = New-Object System.Management.Automation.PSCredential(
            "$($Node.DomainFqdn)\Administrator",
            (ConvertTo-SecureString $Node.Password -AsplainText -Force)
        )

        xComputer SetName {
            Name = $Node.MachineName
        }
        
        xDNSServerAddress SetDNS {
            Address = $Node.DNSIP
            InterfaceAlias = $Node.DNSClientInterfaceAlias
            AddressFamily = "IPv4"
        }
        
        # Make sure AD DS is installed
        WindowsFeature ADDSInstall {
            Ensure = 'Present'
            Name   = 'AD-Domain-Services'
        }

        # Make sure AD DS Tools are installed
        WindowsFeature ADDSTools {
            Ensure = 'Present'
            Name   = 'RSAT-ADDS'
        }

        # Create the Active Directory domain
        xADDomain DC {
            DomainName = $node.DomainFqdn
            DomainNetbiosName = $node.DomainNetBIOS
            DomainAdministratorCredential = $Credential
            SafemodeAdministratorPassword = $Credential
            DependsOn = '[xComputer]SetName', '[WindowsFeature]ADDSInstall'
        }

        # Configure DNS Forwarders on this server
        xDnsServerForwarder Forwarder {
            IsSingleInstance = 'Yes'
            IPAddresses = $node.DnsForwarders
            DependsOn = "[xADDomain]DC"
        }

        # Create a DNS record for AD FS
        xDnsRecord sts {
            Name ='sts'
            Zone = $node.DomainFqdn
            Target = "192.168.1.50"
            Type = "ARecord"
            Ensure = "Present"
        }

        # E   nsure the AD CS role is installed
        WindowsFeature ADCS-Cert-Authority {
            Ensure = 'Present'
            Name = 'ADCS-Cert-Authority'
        }

        # Ensure the AD CS RSAT is installed
        WindowsFeature RSAT-ADCS {
            Ensure = 'Present'
            Name   = 'RSAT-ADCS'
            IncludeAllSubFeature = $true
        }

        # Ensure the AD CS web enrollment role feature is installed
        WindowsFeature ADCS-Web-Enrollment {
            Ensure = 'Present'
            Name   = 'ADCS-Web-Enrollment'
            DependsOn = '[WindowsFeature]ADCS-Cert-Authority' 
        }

        # Ensure the IIS management console is installed for convenience
        WindowsFeature Web-Mgmt-Console {
            Ensure = 'Present'
            Name   = 'Web-Mgmt-Console'
        }

        # Ensure the CA is configured
        xAdcsCertificationAuthority CA {
            Ensure            = 'Present'        
            Credential        = $Credential
            CAType            = 'EnterpriseRootCA'
            CACommonName      = "$($node.DomainNetBIOS) Root CA"
            HashAlgorithmName = 'SHA256'
            DependsOn         = '[WindowsFeature]ADCS-Cert-Authority'
        }

        # Ensure web enrollment is configured
        xAdcsWebEnrollment CertSrv {
            Ensure           = 'Present'
            IsSingleInstance = 'Yes'
            Credential       = $Credential
            DependsOn        = '[WindowsFeature]ADCS-Web-Enrollment','[xAdcsCertificationAuthority]CA' 
        }

        # Create a domain admin user for admin purposes
        xADUser adminUser {
            Ensure     = 'Present'
            DomainName = $node.DomainFqdn
            Username   = $node.DomainAdminUser
            Password   = $Credential
            DisplayName = $node.DomainAdminUserDisplayName
            DependsOn = '[xADDomain]DC'
        }

        # Put the domain admin user into the domain admins group (duh)
        xADGroup DomainAdmins {
            Ensure = 'Present'
            GroupName = 'Domain Admins'
            MembersToInclude = $node.DomainAdminUser
        }
    }
}
