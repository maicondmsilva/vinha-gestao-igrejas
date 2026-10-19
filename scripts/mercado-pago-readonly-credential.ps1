param([switch]$TestReadOnly)
# Human-run alternative for Windows terminals. No secret in arguments or files.
$ErrorActionPreference = 'Stop'
if (-not $TestReadOnly -or $args.Count -gt 0) { throw 'Use somente -TestReadOnly. Nao passe a chave no comando.' }
Add-Type -AssemblyName System.Net.Http
$mpSecureValue = $null
$mpPlainValue = $null
$mpPointer = [IntPtr]::Zero
$mpHandler = $null
$mpClient = $null
$mpRequest = $null
$mpResponse = $null
try {
    $mpSecureValue = Read-Host 'Cole o Access Token DE TESTE (nao a Public Key) e pressione Enter' -AsSecureString
    $mpPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($mpSecureValue)
    $mpPlainValue = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($mpPointer).Trim()
    if ($mpPlainValue -cnotmatch '^(TEST-|APP_USR-)[A-Za-z0-9_-]{10,4000}$') {
        throw 'Formato nao aceito neste diagnostico. Use Access Token, nao Public Key.'
    }
    $mpHandler = [System.Net.Http.HttpClientHandler]::new()
    $mpHandler.AllowAutoRedirect = $false
    $mpClient = [System.Net.Http.HttpClient]::new($mpHandler)
    $mpClient.Timeout = [TimeSpan]::FromSeconds(15)
    $mpRequest = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Get, 'https://api.mercadopago.com/users/me')
    $mpRequest.Headers.Authorization = [System.Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', $mpPlainValue)
    $mpResponse = $mpClient.SendAsync($mpRequest).GetAwaiter().GetResult()
    if (-not $mpResponse.IsSuccessStatusCode) { throw ('Consulta recusada. HTTP ' + [int]$mpResponse.StatusCode) }
    $mpAccount = $mpResponse.Content.ReadAsStringAsync().GetAwaiter().GetResult() | ConvertFrom-Json
    if ($mpAccount.site_id -cne 'MLB' -or $null -eq $mpAccount.id -or [string]$mpAccount.id -notmatch '^[1-9][0-9]*$') { throw 'Conta brasileira nao comprovada.' }
    Write-Host 'Credencial aceita pela API. Conta brasileira confirmada.'
    if (@($mpAccount.tags) -ccontains 'test_user') { Write-Host 'Identidade marcada como teste pelo provedor.' }
    else { Write-Host 'Identidade de teste NAO comprovada. Criacao de assinaturas permanece bloqueada.' }
    Write-Host 'Somente consulta GET; nenhum pagamento, assinatura ou arquivo de credencial criado.'
} catch {
    # Never print exception/request objects: they may contain credential context.
    Write-Host 'Consulta nao concluida. Confira Access Token, conexao e configuracao da conta. Nao compartilhe a chave.'
} finally {
    $mpPlainValue = $null
    if ($mpPointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($mpPointer) }
    if ($mpSecureValue) { $mpSecureValue.Dispose() }
    if ($mpResponse) { $mpResponse.Dispose() }
    if ($mpRequest) { $mpRequest.Dispose() }
    if ($mpClient) { $mpClient.Dispose() }
    if ($mpHandler) { $mpHandler.Dispose() }
    $mpAccount = $null
}
