$rootPath = "d:\ระบบจองรถ"
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:3000/")
try {
    $listener.Start()
    Write-Host "Server started successfully."
    Write-Host "Listening on http://localhost:3000/..."
    Write-Host "Press Ctrl+C or stop task to stop server."
} catch {
    Write-Error "Failed to start listener: $_"
    exit 1
}

while ($listener.IsListening) {
    try {
        $context = $listener.GetContext()
        $request = $context.Request
        $response = $context.Response

        $urlPath = $request.Url.LocalPath
        if ($urlPath -eq "/") {
            $urlPath = "/index.html"
        }

        # URL Decode the request path using native .NET Uri class
        $decodedPath = [System.Uri]::UnescapeDataString($urlPath)
        $filePath = Join-Path $rootPath $decodedPath.TrimStart('/')
        
        # Normalize paths to prevent directory traversal
        $resolvedRoot = [System.IO.Path]::GetFullPath($rootPath)
        $resolvedFile = [System.IO.Path]::GetFullPath($filePath)

        # Inject security response headers
        $response.Headers.Add("X-Content-Type-Options", "nosniff")
        $response.Headers.Add("X-Frame-Options", "DENY")
        $response.Headers.Add("X-XSS-Protection", "1; mode=block")
        $response.Headers.Add("Referrer-Policy", "strict-origin-when-cross-origin")
        $response.Headers.Add("Content-Security-Policy", "default-src 'self'; script-src 'self' 'unsafe-inline' https://cdnjs.cloudflare.com; style-src 'self' 'unsafe-inline' https://cdnjs.cloudflare.com; font-src https://cdnjs.cloudflare.com; img-src 'self' data:; connect-src 'self'")

        if ($resolvedFile.StartsWith($resolvedRoot, [System.StringComparison]::OrdinalIgnoreCase) -and (Test-Path $resolvedFile -PathType Leaf)) {
            $content = [System.IO.File]::ReadAllBytes($resolvedFile)
            
            # Content Type Mapping
            $ext = [System.IO.Path]::GetExtension($resolvedFile).ToLower()
            $contentType = "application/octet-stream"
            switch ($ext) {
                ".html" { $contentType = "text/html; charset=utf-8" }
                ".css"  { $contentType = "text/css; charset=utf-8" }
                ".js"   { $contentType = "application/javascript; charset=utf-8" }
                ".png"  { $contentType = "image/png" }
                ".jpg"  { $contentType = "image/jpeg" }
                ".jpeg" { $contentType = "image/jpeg" }
                ".gif"  { $contentType = "image/gif" }
                ".svg"  { $contentType = "image/svg+xml" }
                ".json" { $contentType = "application/json; charset=utf-8" }
            }

            $response.ContentType = $contentType
            $response.ContentLength64 = $content.Length
            $response.OutputStream.Write($content, 0, $content.Length)
        } else {
            $response.StatusCode = 404
            $msg = [System.Text.Encoding]::UTF8.GetBytes("404 Not Found: $decodedPath")
            $response.ContentType = "text/plain; charset=utf-8"
            $response.ContentLength64 = $msg.Length
            $response.OutputStream.Write($msg, 0, $msg.Length)
        }
        $response.Close()
    } catch {
        # Silent fail for transient client disconnection or other network glitches
    }
}
