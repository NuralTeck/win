param(
    [int]$TimeoutSeconds = 7,
    [string]$OutputFile = ""
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

try {
    Add-Type -AssemblyName System.Speech
    $engine = New-Object System.Speech.Recognition.SpeechRecognitionEngine
    
    # Add standard dictation grammar
    $grammar = New-Object System.Speech.Recognition.DictationGrammar
    $grammar.Name = "LotteryDictation"
    $engine.LoadGrammar($grammar)
    
    # Set to default mic
    $engine.SetInputToDefaultAudioDevice()
    
    # Recognize for specified timeout
    $result = $engine.Recognize([TimeSpan]::FromSeconds($TimeoutSeconds))
    
    $engine.Dispose()
    
    if ($result -and $result.Text) {
        $recognizedText = $result.Text.Trim()
        Write-Output "RECOGNIZED: $recognizedText"
        if ($OutputFile -and (Test-Path -Parent $OutputFile)) {
            [System.IO.File]::WriteAllText($OutputFile, $recognizedText, [System.Text.Encoding]::UTF8)
        }
    } else {
        Write-Output "NO_SPEECH_DETECTED"
    }
} catch {
    Write-Output "ERROR: $($_.Exception.Message)"
}
