$port = 3000
$rootPath = "d:\ระบบจองรถ"

$endpoint = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Loopback, $port)
$listener = New-Object System.Net.Sockets.TcpListener $endpoint

try {
    $listener.Start()
    Write-Host "Server running on http://localhost:$port" -ForegroundColor Green
    Write-Host "กด Ctrl + C เพื่อหยุดทำงาน`n" -ForegroundColor Yellow

    while ($true) {
        if (!$listener.Pending()) {
            Start-Sleep -Milliseconds 100
            continue
        }

        $client = $null
        try {
            $client = $listener.AcceptTcpClient()
            $stream = $client.GetStream()
            
            $buffer = New-Object byte[] 1024
            $bytes = $stream.Read($buffer, 0, $buffer.Length)
            if ($bytes -eq 0) { continue }

            $request = [System.Text.Encoding]::ASCII.GetString($buffer, 0, $bytes)
            
            if ($request -match "^GET\s+(/[^\s\?]*).*HTTP/1\.[01]") {
                $urlPath = $matches[1]
                if ($urlPath -eq "/") { $urlPath = "/index.html" }
                
                # Replace slashes and unescape path
                $unescapedUrl = [System.Uri]::UnescapeDataString($urlPath)
                $filePath = Join-Path $rootPath $unescapedUrl.Replace("/", "\")
                
                # Normalize paths to prevent directory traversal
                $resolvedRoot = [System.IO.Path]::GetFullPath($rootPath)
                $resolvedFile = [System.IO.Path]::GetFullPath($filePath)
                
                # Check if the resolved file is within the root directory and exists as a leaf file
                if ($resolvedFile.StartsWith($resolvedRoot, [System.StringComparison]::OrdinalIgnoreCase) -and (Test-Path $resolvedFile -PathType Leaf)) {
                    $content = [System.IO.File]::ReadAllBytes($resolvedFile)
                    
                    $ext = [System.IO.Path]::GetExtension($resolvedFile).ToLower()
                    $contentType = "text/plain"
                    switch ($ext) {
                        ".html" { $contentType = "text/html; charset=utf-8" }
                        ".css"  { $contentType = "text/css; charset=utf-8" }
                        ".js"   { $contentType = "application/javascript; charset=utf-8" }
                        ".png"  { $contentType = "image/png" }
                        ".jpg"  { $contentType = "image/jpeg" }
                        ".svg"  { $contentType = "image/svg+xml" }
                        ".json" { $contentType = "application/json; charset=utf-8" }
                    }
                    
                    # Construct headers with security defenses
                    $header = "HTTP/1.1 200 OK`r`n" +
                              "Content-Type: $contentType`r`n" +
                              "Content-Length: $($content.Length)`r`n" +
                              "Connection: close`r`n" +
                              "X-Content-Type-Options: nosniff`r`n" +
                              "X-Frame-Options: DENY`r`n" +
                              "X-XSS-Protection: 1; mode=block`r`n" +
                              "Referrer-Policy: strict-origin-when-cross-origin`r`n" +
                              "Content-Security-Policy: default-src 'self'; script-src 'self' 'unsafe-inline' https://cdnjs.cloudflare.com; style-src 'self' 'unsafe-inline' https://cdnjs.cloudflare.com; font-src https://cdnjs.cloudflare.com; img-src 'self' data:; connect-src 'self'`r`n" +
                              "`r`n"
                    $headerBytes = [System.Text.Encoding]::ASCII.GetBytes($header)
                    
                    $stream.Write($headerBytes, 0, $headerBytes.Length)
                    $stream.Write($content, 0, $content.Length)
                } else {
                    $header = "HTTP/1.1 404 Not Found`r`n" +
                              "Content-Type: text/plain; charset=utf-8`r`n" +
                              "Connection: close`r`n" +
                              "X-Content-Type-Options: nosniff`r`n" +
                              "X-Frame-Options: DENY`r`n" +
                              "`r`n" +
                              "File Not Found"
                    $headerBytes = [System.Text.Encoding]::ASCII.GetBytes($header)
                    $stream.Write($headerBytes, 0, $headerBytes.Length)
                }
            }
        } catch {
            Write-Warning "Client Connection Error: $_"
        } finally {
            if ($null -ne $client) { $client.Close() }
        }
    }
} catch {
    Write-Error "ไม่สามารถเปิด Server ได้: $_"
} finally {
    if ($null -ne $listener) { $listener.Stop() }
}