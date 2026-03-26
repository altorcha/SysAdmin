function Configurar-AppLocker {

    Write-Header "CONFIGURAR APPLOCKER"

    try {
        $dominio = Get-ADDomain -ErrorAction Stop
    } catch {
        Write-Fila "ERR" "AD no disponible. Ejecuta primero las opciones 1 y 2."; Write-Host ""; return
    }

    Write-Host "  Reglas que se configuraran via GPO:" -ForegroundColor Gray
    Write-Host ""
    Write-Fila "INF" "Cuates    :  notepad.exe  PERMITIDO  (reglas base)"
    Write-Fila "INF" "NoCuates  :  notepad.exe  BLOQUEADO  por Hash SHA-256"
    Write-Host ""
    Write-Host "  La regla de Hash identifica el ejecutable por contenido," -ForegroundColor Gray
    Write-Host "  no por nombre. Renombrar el .exe no evita el bloqueo."    -ForegroundColor Gray
    Write-Host ""

    if (-not (Confirm-Accion "Deseas continuar?")) {
        Write-Sep; Write-Fila "INF" "Cancelado por el usuario."; Write-Host ""; return
    }

    # -- SID de NoCuates --
    Write-Host "  Obteniendo SID del grupo NoCuates..." -ForegroundColor Gray

    try {
        $sidNoCuates = (Get-ADGroup -Identity "NoCuates").SID.Value
        Write-Fila "OK" "SID NoCuates  ->  $sidNoCuates"
    } catch {
        Write-Fila "ERR" "No se pudo obtener el SID  :  $($_.Exception.Message)"; return
    }

    $hashValor   = "0xA5FB2A35F78C2FBCB1F1329FF1C8123A5B9CFF95653C15381339599251D6D26D"
    $archivoSize = 201216
    $guid1       = [System.Guid]::NewGuid().ToString()

    # -- Construir XML --
    Write-Host ""
    Write-Host "  Construyendo politica AppLocker..." -ForegroundColor Gray

    $xmlPolicy = @"
<AppLockerPolicy Version="1">
  <RuleCollection Type="Exe" EnforcementMode="Enabled">
    <FilePathRule Id="921cc481-6e17-4653-8f75-050b80acca20" Name="Permitir Windows" Description="" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions><FilePathCondition Path="%WINDIR%\*"/></Conditions>
    </FilePathRule>
    <FilePathRule Id="a61c8b2c-a23e-47ff-8e4a-4e3d41bc98b0" Name="Permitir ProgramFiles" Description="" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions><FilePathCondition Path="%PROGRAMFILES%\*"/></Conditions>
    </FilePathRule>
    <FilePathRule Id="b61c8b2c-a23e-47ff-8e4a-4e3d41bc98b1" Name="Permitir ProgramFiles x86" Description="" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions><FilePathCondition Path="%PROGRAMFILES(X86)%\*"/></Conditions>
    </FilePathRule>
    <FileHashRule Id="$guid1" Name="Bloquear Notepad NoCuates" Description="Bloquea notepad.exe por hash - renombrar no evita el bloqueo" UserOrGroupSid="$sidNoCuates" Action="Deny">
      <Conditions>
        <FileHashCondition>
          <FileHash Type="SHA256" Data="$hashValor" SourceFileName="notepad.exe" SourceFileLength="$archivoSize"/>
        </FileHashCondition>
      </Conditions>
    </FileHashRule>
  </RuleCollection>
  <RuleCollection Type="Appx" EnforcementMode="Enabled">
    <FilePublisherRule Id="a9e18c21-ff8f-43cf-b9fc-db40eed693ba" Name="Permitir apps Microsoft" Description="" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePublisherCondition PublisherName="CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US" ProductName="*" BinaryName="*">
          <BinaryVersionRange LowSection="*" HighSection="*"/>
        </FilePublisherCondition>
      </Conditions>
    </FilePublisherRule>
    <FilePublisherRule Id="b9e18c21-ff8f-43cf-b9fc-db40eed693bb" Name="Permitir apps Windows" Description="" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePublisherCondition PublisherName="CN=Microsoft Windows, O=Microsoft Corporation, L=Redmond, S=Washington, C=US" ProductName="*" BinaryName="*">
          <BinaryVersionRange LowSection="*" HighSection="*"/>
        </FilePublisherCondition>
      </Conditions>
    </FilePublisherRule>
  </RuleCollection>
</AppLockerPolicy>
"@

    $xmlPath = "C:\Windows\Temp\applocker_p8.xml"
    $xmlPolicy | Out-File $xmlPath -Encoding UTF8 -Force
    Write-Fila "OK" "XML generado  ->  $xmlPath"

    # -- GPO --
    Write-Host ""
    Write-Host "  Configurando GPO de AppLocker..." -ForegroundColor Gray
    Write-Host ""

    $gpoNombre = "Practica8-AppLocker"

    try {
        $gpo = Get-GPO -Name $gpoNombre -ErrorAction SilentlyContinue
        if (-not $gpo) {
            $gpo = New-GPO -Name $gpoNombre
            Write-Fila "NEW" "GPO creada  ->  $gpoNombre"
        } else {
            Write-Fila "UPD" "GPO ya existe, se actualiza  ->  $gpoNombre"
        }

        $gpoId = $gpo.Id.ToString()
        Set-AppLockerPolicy -XmlPolicy $xmlPath -Ldap "LDAP://CN={$gpoId},CN=Policies,CN=System,DC=practica8,DC=local"
        Write-Fila "OK" "Politica AppLocker aplicada a la GPO."

        try {
            New-GPLink -Name $gpoNombre -Target $dominio.DistinguishedName -ErrorAction Stop | Out-Null
            Write-Fila "OK" "GPO vinculada al dominio."
        } catch {
            Write-Fila "UPD" "GPO ya estaba vinculada al dominio."
        }

        Write-Host ""
        Write-Host "  Habilitando servicio AppIDSvc..." -ForegroundColor Gray
        sc.exe config AppIDSvc start= auto | Out-Null
        sc.exe start  AppIDSvc 2>$null    | Out-Null
        Write-Fila "OK" "AppIDSvc configurado como Automatico."

    } catch {
        Write-Fila "ERR" "No se pudo configurar la GPO  :  $($_.Exception.Message)"; return
    }

    Write-Host ""
    Write-Sep
    Write-Fila "OK"  "Cuates    :  notepad.exe  PERMITIDO"
    Write-Fila "OK"  "NoCuates  :  notepad.exe  BLOQUEADO  (hash)"
    Write-Host ""
    Write-Host "  Pasos requeridos en el cliente Windows:" -ForegroundColor Gray
    Write-Host ""
    Write-Fila "INF" "1.  Abrir PowerShell como Administrador"
    Write-Fila "INF" "2.  sc.exe config AppIDSvc start= auto"
    Write-Fila "INF" "3.  sc.exe start AppIDSvc"
    Write-Fila "INF" "4.  gpupdate /force"
    Write-Fila "INF" "5.  Cerrar sesion y volver a entrar"
    Write-Host ""
}
