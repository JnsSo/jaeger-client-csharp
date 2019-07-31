[CmdletBinding(PositionalBinding = $false)]
param(
    [string] $ArtifactsPath = (Join-Path $PWD "artifacts"),
    [string] $BuildConfiguration = "Release",

    [bool] $RunBuild = $true,
    [bool] $RunTests = $false,
    [bool] $RunXdock = $true
)

$ErrorActionPreference = "Stop"
$Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

function Task {
    [CmdletBinding()] param (
        [Parameter(Mandatory = $true)] [string] $name,
        [Parameter(Mandatory = $false)] [bool] $runTask,
        [Parameter(Mandatory = $false)] [scriptblock] $cmd
    )

    if ($cmd -eq $null) {
        throw "Command is missing for task '$name'. Make sure the starting '{' is on the same line as the term 'Task'. E.g. 'Task `"$name`" `$Run$name {'"
    }

    if ($runTask -eq $true) {
        Write-Host "`n------------------------- [$name] -------------------------`n" -ForegroundColor Cyan
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        & $cmd
        Write-Host "`nTask '$name' finished in $($sw.Elapsed.TotalSeconds) sec."
    }
    else {
        Write-Host "`n------------------ Skipping task '$name' ------------------" -ForegroundColor Yellow
    }
}


Task "Init" $true {

    if ($ArtifactsPath -eq $null) { "Property 'ArtifactsPath' may not be null." }
    if ($BuildConfiguration -eq $null) { throw "Property 'BuildConfiguration' may not be null." }
    if ((Get-Command "dotnet" -ErrorAction SilentlyContinue) -eq $null) { throw "'dotnet' command not found. Is .NET Core SDK installed?" }
	
	#choco install make
    #Write-Host "Installed make"
	
	#choco upgrade docker-desktop
    #Write-Host "Upgrade docker-desktop"
	
	#choco upgrade docker-compose
    #Write-Host "Upgrade docker-compose"

    Write-Host "ArtifactsPath: $ArtifactsPath"
    Write-Host "BuildConfiguration: $BuildConfiguration"
    Write-Host ".NET Core SDK: $(dotnet --version)"
    Write-Host "Docker: $(docker version)"
    Write-Host "Docker Compose: $(docker-compose version)`n"

    Remove-Item -Path $ArtifactsPath -Recurse -Force -ErrorAction Ignore
    New-Item $ArtifactsPath -ItemType Directory -ErrorAction Ignore | Out-Null
    Write-Host "Created artifacts folder '$ArtifactsPath'"
}

Task "Build" $RunBuild {

    dotnet msbuild "/t:Restore;Build;Pack" "/p:CI=true" `
        "/p:Configuration=$BuildConfiguration" `
        "/p:PackageOutputPath=$(Join-Path $ArtifactsPath "nuget")"

    if ($LASTEXITCODE -ne 0) { throw "Build failed." }
}

Task "Tests" $RunTests {

    $testsFailed = $false
    Get-ChildItem -Filter *.csproj -Recurse | ForEach-Object {

        if (Select-Xml -Path $_.FullName -XPath "/Project/ItemGroup/PackageReference[@Include='Microsoft.NET.Test.Sdk']") {
            dotnet test $_.FullName -c $BuildConfiguration --no-build
            if ($LASTEXITCODE -ne 0) { $testsFailed = $true }
        }
    }

    if ($testsFailed) { throw "At least one test failed." }
}

Task "Xdock" $RunXdock {

	# make crossdock
	
	# Only for testing...
	docker build -f crossdock/Dockerfile -t test .
	
	$xdockYaml = "crossdock/docker-compose.yml"
	docker-compose -f $xdockYaml build csharp
	docker-compose -f $xdockYaml run crossdock
	
    if ($LASTEXITCODE -ne 0) { throw "Crossdock failed." }
}

Write-Host "`nBuild finished in $($Stopwatch.Elapsed.TotalSeconds) sec." -ForegroundColor Green
