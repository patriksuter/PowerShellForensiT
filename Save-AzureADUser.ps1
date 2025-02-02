﻿
# Check that AzureAD is installed
if (-Not (Get-Module -ListAvailable -Name AzureAD)) {

    $install = Read-Host 'The AzureAD PowerShell module is not installed. Do you want to install it now? (Y/n)'

    if($install -eq '' -Or $install -eq 'Y' -Or $install -eq 'Yes'){
        If (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator"))
        {
            Write-Warning "Administrator permissions are needed to install the AzureAD PowerShell module.`nPlease re-run this script as an Administrator."
            Exit
        }

        write-host "Installing"
        Install-Module -Name AzureAD
    }
    else {
        exit
    }
}

Function Remove-Chars {
    param ([String]$src = [String]::Empty)
    #replace diacritics
    $normalized = $src.Normalize( [Text.NormalizationForm]::FormD )
    $sb = new-object Text.StringBuilder
    $normalized.ToCharArray() | % {
        if( [Globalization.CharUnicodeInfo]::GetUnicodeCategory($_) -ne [Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$sb.Append($_)
        }
    }
    $sb=$sb.ToString()
    #replace via code page conversion
    $NonUnicodeEncoding = [System.Text.Encoding]::GetEncoding(850)
    $UnicodeEncoding = [System.Text.Encoding]::Unicode
    [Byte[]] $UnicodeBytes = $UnicodeEncoding.GetBytes($sb);
    [Byte[]] $NonUnicodeBytes = [System.Text.Encoding]::Convert($UnicodeEncoding, $NonUnicodeEncoding , $UnicodeBytes);
    [Char[]] $NonUnicodeChars = New-Object -TypeName “Char[]” -ArgumentList $($NonUnicodeEncoding.GetCharCount($NonUnicodeBytes, 0, $NonUnicodeBytes.Length))
    [void] $NonUnicodeEncoding.GetChars($NonUnicodeBytes, 0, $NonUnicodeBytes.Length, $NonUnicodeChars, 0);
    [String] $NonUnicodeString = New-Object String(,$NonUnicodeChars)
    $NonUnicodeString
}

# Create a temporary file to hold the unformatted results of our Get-AzureADUser query
$TempFile = New-TemporaryFile

#Go ahead and attempt to get the Azure AD user IDs, but catch the error if there is no existing connection to Azure AD
Try
{
    Get-AzureADUser -All:$true | Export-Csv -Path $TempFile -NoTypeInformation -encoding Utf8
}
Catch [Microsoft.Open.Azure.AD.CommonLibrary.AadNeedAuthenticationException]
{
    #Connect to Azure AD. This will show a prompt.
    Connect-AzureAD | Out-Null

    #Try again
    Get-AzureADUser -All:$true | Export-Csv -Path $TempFile -NoTypeInformation -encoding Utf8
}


# Get the tennant details
$Tenant = Get-AzureADTenantDetail

# Get the unformatted data from the temporary file
$azureADUsers = import-csv $TempFile

# Create the XML file
$xmlsettings = New-Object System.Xml.XmlWriterSettings
$xmlsettings.Indent = $true
$xmlsettings.IndentChars = "    "

$XmlWriter = [System.XML.XmlWriter]::Create("$((Get-Location).Path)\ForensiTAzureID.xml", $xmlsettings)

# Write the XML Declaration and set the XSL
$xmlWriter.WriteStartDocument()
$xmlWriter.WriteProcessingInstruction("xml-stylesheet", "type='text/xsl' href='style.xsl'")

# Start the Root Element 
$xmlWriter.WriteStartElement("ForensiTAzureID")

# Write the Azure AD domain details as attributes
$xmlWriter.WriteAttributeString("ObjectId", $($Tenant.ObjectId))
$xmlWriter.WriteAttributeString("Name", $($Tenant.VerifiedDomains.Name));
$xmlWriter.WriteAttributeString("DisplayName", $($Tenant.DisplayName));


#Parse the data
ForEach ($azureADUser in $azureADUsers){
  
    $xmlWriter.WriteStartElement("User")

        $xmlWriter.WriteElementString("UserPrincipalName",$($azureADUser.UserPrincipalName))
        $xmlWriter.WriteElementString("ObjectId",$($azureADUser.ObjectId))
        $xmlWriter.WriteElementString("DisplayName",$(Remove-Chars $azureADUser.DisplayName))

    $xmlWriter.WriteEndElement()
    }

$xmlWriter.WriteEndElement()

# Close the XML Document
$xmlWriter.WriteEndDocument()
$xmlWriter.Flush()
$xmlWriter.Close()


# Clean up
Remove-Item $TempFile
 
write-host "Azure user ID file created: $((Get-Location).Path)\ForensiTAzureID.xml"

