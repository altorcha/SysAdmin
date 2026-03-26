function Write-Header {
    param([string]$Titulo)
    $linea  = "=" * 64
    $espacio = 64 - $Titulo.Length
    $izq    = [math]::Floor($espacio / 2)
    $centro = (" " * $izq) + $Titulo
    Write-Host ""
    Write-Host "  $linea"  -ForegroundColor DarkCyan
    Write-Host "  $centro" -ForegroundColor White
    Write-Host "  $linea"  -ForegroundColor DarkCyan
    Write-Host ""
}

function Write-Sep {
    Write-Host "  $("-" * 64)" -ForegroundColor DarkCyan
}

function Write-Fila {
    param(
        [string]$Estado,
        [string]$Mensaje
    )
    switch ($Estado) {
        "OK"  { $tag = " OK "; $col = "Green"      }
        "ERR" { $tag = "ERR "; $col = "Red"        }
        "AVS" { $tag = "AVS "; $col = "DarkYellow" }
        "NEW" { $tag = "NEW "; $col = "Cyan"       }
        "UPD" { $tag = "UPD "; $col = "Yellow"     }
        "INF" { $tag = " -- "; $col = "Gray"       }
        default { $tag = "    "; $col = "Gray"     }
    }
    Write-Host "  [ $tag ]  $Mensaje" -ForegroundColor $col
}

function Write-Resumen {
    param([hashtable[]]$Filas)
    Write-Host ""
    Write-Sep
    foreach ($f in $Filas) {
        $etiqueta = $f.Label.PadRight(26)
        $valor    = "$($f.Valor)".PadLeft(4)
        Write-Host "  $etiqueta  $valor" -ForegroundColor $f.Color
    }
    Write-Sep
    Write-Host ""
}

function Confirm-Accion {
    param([string]$Pregunta = "Deseas continuar?")
    $r = Read-Host "  $Pregunta (s/n)"
    Write-Host ""
    return ($r -eq "s")
}
