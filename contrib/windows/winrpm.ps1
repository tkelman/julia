# Download an RPM and its dependencies, usage:
# winrpm.ps1 http://download.opensuse.org/repositories/windows:/mingw:/win64/openSUSE_13.1/ mingw64-hdf5

$url = 'http://download.opensuse.org/repositories/windows:mingw:/win64/openSUSE_13.1/'
[Xml]$repomd = (New-Object Net.WebClient).DownloadString($url + 'repodata/repomd.xml')
$ns = New-Object Xml.XmlNamespaceManager($repomd.NameTable)
$ns.AddNamespace('ns', $repomd.DocumentElement.NamespaceURI)
$primarygz = (New-Object Net.WebClient).DownloadData($url + $repomd.SelectSingleNode( `
    "/ns:repomd/ns:data[@type='primary']/ns:location/@href", $ns).'#text')

# I don't understand how `curl | gunzip` can possibly require this many lines of code?!?
$instream = New-Object IO.MemoryStream
$outstream = New-Object IO.MemoryStream
$gz = New-Object IO.Compression.GZipStream($instream, ([IO.Compression.CompressionMode]::Decompress))
$instream.Write($primarygz, 0, $primarygz.Length)
$instream.Position = 0
try {
    $buffer = New-Object byte[](1024)
    while (1) {
        $count = $gz.Read($buffer, 0, 1024)
        if ($count -le 0) {
            break
        }
        $outstream.Write($buffer, 0, $count)
    }
}
finally {
    [Xml]$primary = ([System.Text.Encoding]::ASCII).GetString($outstream.ToArray())
    $gz.Close();
    $outstream.Close();
    $instream.Close();
}

$ns = New-Object Xml.XmlNamespaceManager($primary.NameTable)
$ns.AddNamespace('ns', $primary.DocumentElement.NamespaceURI)
$ns.AddNamespace('rpm', $primary.DocumentElement.rpm)

$primary.SelectNodes("//ns:package[ns:name='mingw64-hdf5' and ns:arch='noarch']", $ns)





[Xml]$prim2 = Get-Content 'D:\cygwin64\home\Tony\julia\contrib\windows\primary.xml'
$prim2.SelectNodes("//ns:package[ns:name='mingw64-libgit2' and ns:arch='noarch']/ `
    ns:format/rpm:requires", $ns)

$prim2.SelectNodes("//ns:package[ns:name='mingw64-hdf5' and ns:arch='noarch']", $ns)[0].version
$prim2.SelectNodes("//ns:package[ns:name='mingw64-hdf5' and ns:arch='noarch']", $ns)[1].version

