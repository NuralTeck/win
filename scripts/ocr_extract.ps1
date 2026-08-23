param (
    [Parameter(Mandatory=$true)]
    [string]$ImagePath
)

try {
    Add-Type -AssemblyName System.Runtime.WindowsRuntime
    [Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime] | Out-Null
    [Windows.Graphics.Imaging.BitmapDecoder, Windows.Graphics.Imaging, ContentType = WindowsRuntime] | Out-Null
    [Windows.Media.Ocr.OcrEngine, Windows.Media.Ocr, ContentType = WindowsRuntime] | Out-Null

    $asyncFileOp = [Windows.Storage.StorageFile]::GetFileFromPathAsync($ImagePath)
    $asTask = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name.StartsWith('IAsyncOperation') } | Select-Object -First 1
    
    $fileTask = $asTask.MakeGenericMethod([Windows.Storage.StorageFile]).Invoke($null, @($asyncFileOp))
    $fileTask.Wait()
    $storageFile = $fileTask.Result

    $asyncStreamOp = $storageFile.OpenAsync([Windows.Storage.FileAccessMode]::Read)
    $streamTask = $asTask.MakeGenericMethod([Windows.Storage.Streams.IRandomAccessStream]).Invoke($null, @($asyncStreamOp))
    $streamTask.Wait()
    $stream = $streamTask.Result

    $asyncDecoderOp = [Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)
    $decoderTask = $asTask.MakeGenericMethod([Windows.Graphics.Imaging.BitmapDecoder]).Invoke($null, @($asyncDecoderOp))
    $decoderTask.Wait()
    $decoder = $decoderTask.Result

    $asyncBitmapOp = $decoder.GetSoftwareBitmapAsync()
    $bitmapTask = $asTask.MakeGenericMethod([Windows.Graphics.Imaging.SoftwareBitmap]).Invoke($null, @($asyncBitmapOp))
    $bitmapTask.Wait()
    $softwareBitmap = $bitmapTask.Result

    $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
    if (-not $engine) {
        $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage([Windows.Globalization.Language]::new("en-US"))
    }

    $asyncOcrOp = $engine.RecognizeAsync($softwareBitmap)
    $ocrTask = $asTask.MakeGenericMethod([Windows.Media.Ocr.OcrResult]).Invoke($null, @($asyncOcrOp))
    $ocrTask.Wait()
    $result = $ocrTask.Result

    Write-Output $result.Text
} catch {
    Write-Error $_.Exception.Message
}
