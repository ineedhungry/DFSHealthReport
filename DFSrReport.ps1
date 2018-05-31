#-----------------------------------------------------------------------
$To = ‘EMAIL@EMAIL.COM’
$From = ‘DFSREPORT@EMAIL.COM’
$Subject = "DFS Health Report - $((get-date).ToString('MM/dd/yyyy'))"
$MailServer = ‘EMAILSERVER.EMAIL.COM’
$Domain = ‘ADDOMAIN.COM’
#-----------------------------------------------------------------------
#-----------------------------------------------------------------------
$CSS = @"
<style>
h1, h5, th, p { text-align: center; }
table { margin: auto; font-family: Segoe UI; box-shadow: 10px 10px 5px #888; border: 1px solid black; border-collapse: collapse; }
table tbody tr td table { box-shadow: 0px 0px 0px #888 }
table tbody tr td table tbody { width: aut; }
th { border: 1px solid black; background: #dddddd; color: #000000; max-width: 400px; padding: 5px 10px; }
td { border: 1px solid black; font-size: 11px; padding: 5px 20px; color: #000; }
tr { background: #b8d1f3; }
tr:nth-child(even) { background: #fff; }
tr:nth-child(odd) { background: #f9fbfe; }
</style>
"@
#-----------------------------------------------------------------------
#-----------------------------------------------------------------------
$body = @"
<h1>DFSr Report</h1>
<p>The following report was run on $(get-date).</p>
"@
#-----------------------------------------------------------------------
Add-Type -AssemblyName System.Web
Import-Module DFSR
$Groups = dfsradmin rg list /Domain:$Domain /attr:rgname /CSV | Where-Object {-not($_ -like 'RgName' -or $_ -like "")}
$DFSMembers = Foreach ($Group in $Groups)
{
    $Replication = Get-DfsReplicationGroup -GroupName $Group
    $DFSName = $Replication.GroupName
    $Connection =  Get-DfsrConnection -GroupName $Group
    $ReveivingMember = $Connection.DestinationComputerName | Select-Object -First 1
    $SourceMember = $Connection.SourceComputerName | Select-Object -First 1
    $DFSAppName = $DFSName.substring($DFSName.LastIndexOf('\') + 1, $DFSName.Length - ($DFSName.LastIndexOf('\') + 1))
    $backlog = dfsrdiag backlog /receivingmember:$ReveivingMember /sendingmember:$SourceMember /RGname:$DFSName /RFname:$DFSAppName
        If ($backlog -eq $null) 
        {
            $backlogcount = "0";
        }
        Else 
        {
            $backlogcount = ($backlog[1]).split(":")[1];
            $backlogcount = $backlogcount.trim();
        }          
        $Servers = Foreach ($Computer in $Connection.SourceComputerName) 
        {
            $Shares = Invoke-Command -ComputerName $Computer -ScriptBlock {Get-SmbShare | Select-Object Name,Path}
            Foreach ($Share in $Shares) 
            {
                $Name = $Share.Name
                If ($Name -ne "")
                {
                    If ($Name -eq $DFSAppName) 
                    {
                        $DriveLetter = ($Share.Path).Substring(0,1)
                        $DriveLetter = $DriveLetter.Trim()
                    }                                                        

                }
            }
            $driveSpace = Invoke-Command -ComputerName $Computer -ScriptBlock {Get-PSDrive $using:DriveLetter}
            $driveSpaceRoundUsed = [math]::round($driveSpace.Used /1Tb, 2)
            $driveSpaceRoundFree = [math]::round($driveSpace.Free /1Tb, 2)
            $driveTotalSize = $driveSpaceRoundUsed + $driveSpaceRoundFree
            If ($driveTotalSize -eq 0) 
            {
                $precentFree = 0
                $precentUsed = 0
            }
            Else 
            {
                $precentFree = ($driveSpaceRoundFree/$driveTotalSize)
                $precentUsed = ($driveSpaceRoundUsed/$driveTotalSize)
            }
                $Used = "$driveSpaceRoundUsed TB $(($precentUsed).tostring("P"))"
                $Free = "$driveSpaceRoundFree TB $(($precentFree).tostring("P"))" 
                $Total = "$driveTotalSize TB"
                If ($precentFree -lt 0.05)
                {
                    $Warn = "LOW"
                }
                Else 
                {
                    $Warn = "OK"
                }               
            [PSCustomObject]@{
                Server = $Computer
                Used = $Used
                Free = $Free
                Total = $Total
                Space = $Warn    
            }
        }        
    [PSCustomObject]@{
        DFSGroup = $Replication.GroupName
        Members = [String]($Servers | ConvertTo-Html -Fragment | Foreach-Object {$PSItem -replace "<td>OK</td>", "<td style='background-color:#008000;color:#FFF'>OK</td>" -replace "<td>LOW</td>", "<td style='background-color:#800000;color:#FFF'>LOW</td>"})
        BackLogFiles = $backlogcount
        Status = $Replication.State
    }
            

        
}
$HTML = $DFSMembers | ConvertTo-Html -Head $CSS -Body $body | Foreach-Object {$PSItem -replace "<td style='background-color:#BDB76B;color:#FFF'>" -replace "<td>Normal</td>", "<td style='background-color:#008000;color:#FFF'>Normal</td>" -replace "<td>0</td>", "<td style='background-color:#008000;color:#FFF'>0</td>"}
$Body = [System.Web.HttpUtility]::HtmlDecode($HTML)

$message = new-object System.Net.Mail.MailMessage 
$message.From = $From
$message.To.Add($To) 
$message.IsBodyHtml = $True 
$message.Subject = $Subject 
$message.body = $body 
$smtp = new-object Net.Mail.SmtpClient($MailServer) 
$smtp.Send($message)
