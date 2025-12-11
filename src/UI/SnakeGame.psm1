# ==============================================================================
# SnakeGame.psm1
# Mini-jeu Snake jouable pendant l'export/import
# ==============================================================================

Add-Type -AssemblyName PresentationFramework

# Variables du jeu
$script:SnakeTimer = $null
$script:Snake = @()
$script:Direction = "Right"
$script:NextDirection = "Right"
$script:Food = $null
$script:Score = 0
$script:BestScore = 0
$script:GameOver = $false
$script:GridSize = 20
$script:CanvasWidth = 0
$script:CanvasHeight = 0

function Initialize-SnakeGame {
    <#
    .SYNOPSIS
    Initialise le jeu Snake
    #>
    param(
        [Parameter(Mandatory=$true)]
        $Canvas,

        [Parameter(Mandatory=$true)]
        $ScoreText,

        [Parameter(Mandatory=$true)]
        $BestScoreText
    )

    $script:SnakeCanvas = $Canvas
    $script:SnakeScoreText = $ScoreText
    $script:SnakeBestScoreText = $BestScoreText

    # Calculer dimensions de la grille
    $script:CanvasWidth = [Math]::Floor($Canvas.Width / $script:GridSize) * $script:GridSize
    $script:CanvasHeight = [Math]::Floor($Canvas.Height / $script:GridSize) * $script:GridSize

    # Événement clavier sur la FENÊTRE PRINCIPALE (pas le canvas)
    $mainWindow = [System.Windows.Application]::Current.MainWindow
    if ($mainWindow) {
        $mainWindow.Add_PreviewKeyDown({
            param($sender, $e)

            # Empêcher le comportement par défaut qui défile la page
            if ($e.Key -in @('Up', 'Down', 'Left', 'Right', 'Space')) {
                $e.Handled = $true
            }

            switch ($e.Key) {
                "Up"    { if ($script:Direction -ne "Down")  { $script:NextDirection = "Up" } }
                "Down"  { if ($script:Direction -ne "Up")    { $script:NextDirection = "Down" } }
                "Left"  { if ($script:Direction -ne "Right") { $script:NextDirection = "Left" } }
                "Right" { if ($script:Direction -ne "Left")  { $script:NextDirection = "Right" } }
                "Space" { if ($script:GameOver) { Start-SnakeGame } }
            }
        })
    }

    # Donner le focus au canvas
    $Canvas.Focus()

    Write-MWLogInfo "Snake Game initialisé (${script:CanvasWidth}x${script:CanvasHeight})"
}

function Start-SnakeGame {
    <#
    .SYNOPSIS
    Démarre une nouvelle partie
    #>

    # Réinitialiser le jeu
    $script:Snake = @(
        @{X = 5; Y = 5},
        @{X = 4; Y = 5},
        @{X = 3; Y = 5}
    )

    $script:Direction = "Right"
    $script:NextDirection = "Right"
    $script:Score = 0
    $script:GameOver = $false

    # Générer première nourriture
    New-Food

    # Dessiner l'état initial
    Draw-SnakeGame

    # Démarrer le timer (150ms = plus lent, plus stable, pas de freeze)
    if ($script:SnakeTimer) {
        $script:SnakeTimer.Stop()
    }

    $script:SnakeTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:SnakeTimer.Interval = [TimeSpan]::FromMilliseconds(150)
    $script:SnakeTimer.Add_Tick({
        Update-SnakeGame
    })
    $script:SnakeTimer.Start()

    Write-MWLogInfo "Snake Game démarré"
}

function Stop-SnakeGame {
    <#
    .SYNOPSIS
    Arrête le jeu
    #>

    if ($script:SnakeTimer) {
        $script:SnakeTimer.Stop()
        $script:SnakeTimer = $null
    }

    Write-MWLogInfo "Snake Game arrêté"
}

function Update-SnakeGame {
    <#
    .SYNOPSIS
    Met à jour l'état du jeu (appelé par le timer)
    #>

    if ($script:GameOver) {
        return
    }

    # Appliquer la prochaine direction
    $script:Direction = $script:NextDirection

    # Calculer nouvelle position de la tête
    $head = $script:Snake[0]
    $newHead = @{X = $head.X; Y = $head.Y}

    switch ($script:Direction) {
        "Up"    { $newHead.Y -= 1 }
        "Down"  { $newHead.Y += 1 }
        "Left"  { $newHead.X -= 1 }
        "Right" { $newHead.X += 1 }
    }

    # Vérifier collision avec les murs
    $cols = [Math]::Floor($script:CanvasWidth / $script:GridSize)
    $rows = [Math]::Floor($script:CanvasHeight / $script:GridSize)

    if ($newHead.X -lt 0 -or $newHead.X -ge $cols -or
        $newHead.Y -lt 0 -or $newHead.Y -ge $rows) {
        End-SnakeGame
        return
    }

    # Vérifier collision avec soi-même
    foreach ($segment in $script:Snake) {
        if ($newHead.X -eq $segment.X -and $newHead.Y -eq $segment.Y) {
            End-SnakeGame
            return
        }
    }

    # Ajouter nouvelle tête
    $script:Snake = @($newHead) + $script:Snake

    # Vérifier si mange la nourriture
    if ($newHead.X -eq $script:Food.X -and $newHead.Y -eq $script:Food.Y) {
        $script:Score++
        New-Food

        # Mettre à jour le meilleur score
        if ($script:Score -gt $script:BestScore) {
            $script:BestScore = $script:Score
        }
    }
    else {
        # Retirer la queue
        $script:Snake = $script:Snake[0..($script:Snake.Count - 2)]
    }

    # Redessiner
    Draw-SnakeGame
}

function New-Food {
    <#
    .SYNOPSIS
    Génère une nouvelle nourriture à une position aléatoire
    #>

    $cols = [Math]::Floor($script:CanvasWidth / $script:GridSize)
    $rows = [Math]::Floor($script:CanvasHeight / $script:GridSize)

    do {
        $script:Food = @{
            X = Get-Random -Minimum 0 -Maximum $cols
            Y = Get-Random -Minimum 0 -Maximum $rows
        }

        # Vérifier que la nourriture n'est pas sur le serpent
        $onSnake = $false
        foreach ($segment in $script:Snake) {
            if ($script:Food.X -eq $segment.X -and $script:Food.Y -eq $segment.Y) {
                $onSnake = $true
                break
            }
        }
    } while ($onSnake)
}

function Draw-SnakeGame {
    <#
    .SYNOPSIS
    Dessine l'état actuel du jeu
    #>

    # Effacer le canvas
    $script:SnakeCanvas.Children.Clear()

    # Dessiner le serpent
    $isHead = $true
    foreach ($segment in $script:Snake) {
        $rect = New-Object System.Windows.Shapes.Rectangle
        $rect.Width = $script:GridSize - 2
        $rect.Height = $script:GridSize - 2
        $rect.Fill = if ($isHead) { "#00ff88" } else { "#00cc66" }
        $rect.RadiusX = 3
        $rect.RadiusY = 3

        [System.Windows.Controls.Canvas]::SetLeft($rect, $segment.X * $script:GridSize + 1)
        [System.Windows.Controls.Canvas]::SetTop($rect, $segment.Y * $script:GridSize + 1)

        $script:SnakeCanvas.Children.Add($rect) | Out-Null
        $isHead = $false
    }

    # Dessiner la nourriture
    if ($script:Food) {
        $foodCircle = New-Object System.Windows.Shapes.Ellipse
        $foodCircle.Width = $script:GridSize - 4
        $foodCircle.Height = $script:GridSize - 4
        $foodCircle.Fill = "#ff3366"

        [System.Windows.Controls.Canvas]::SetLeft($foodCircle, $script:Food.X * $script:GridSize + 2)
        [System.Windows.Controls.Canvas]::SetTop($foodCircle, $script:Food.Y * $script:GridSize + 2)

        $script:SnakeCanvas.Children.Add($foodCircle) | Out-Null
    }

    # Mettre à jour le score
    $script:SnakeScoreText.Text = $script:Score.ToString()
    $script:SnakeBestScoreText.Text = $script:BestScore.ToString()

    # Afficher Game Over si nécessaire
    if ($script:GameOver) {
        $gameOverText = New-Object System.Windows.Controls.TextBlock
        $gameOverText.Text = "GAME OVER`nScore: $($script:Score)`n`nAppuyez sur ESPACE pour rejouer"
        $gameOverText.FontSize = 24
        $gameOverText.FontWeight = "Bold"
        $gameOverText.Foreground = "#ff3366"
        $gameOverText.TextAlignment = "Center"

        $centerX = ($script:CanvasWidth / 2) - 150
        $centerY = ($script:CanvasHeight / 2) - 50

        [System.Windows.Controls.Canvas]::SetLeft($gameOverText, $centerX)
        [System.Windows.Controls.Canvas]::SetTop($gameOverText, $centerY)

        $script:SnakeCanvas.Children.Add($gameOverText) | Out-Null
    }
}

function End-SnakeGame {
    <#
    .SYNOPSIS
    Termine la partie
    #>

    $script:GameOver = $true

    if ($script:SnakeTimer) {
        $script:SnakeTimer.Stop()
    }

    Draw-SnakeGame

    Write-MWLogInfo "Snake Game terminé - Score: $($script:Score)"
}

Export-ModuleMember -Function @(
    'Initialize-SnakeGame',
    'Start-SnakeGame',
    'Stop-SnakeGame'
)
