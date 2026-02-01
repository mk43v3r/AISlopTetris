module Main exposing (main)

import Browser
import Browser.Events exposing (onKeyDown)
import Html exposing (Html, div, h1, h2, p, text, button, audio, source)
import Html.Attributes exposing (style, class, src, id, autoplay, loop, attribute)
import Html.Events exposing (onClick)
import Json.Decode as Decode
import Random
import Time
import Task
import Process
import Svg exposing (svg, rect, g, Svg)
import Svg.Attributes as SvgAttr


-- MAIN

main : Program () Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , subscriptions = subscriptions
        , view = view
        }


-- MODEL

type alias Model =
    { board : Board
    , currentPiece : Maybe Piece
    , nextPieces : List TetrominoType
    , score : Int
    , level : Int
    , linesCleared : Int
    , gameState : GameState
    , dropSpeed : Float
    , clearingRows : List Int
    , animationFrame : Float
    , lastSound : String
    , heldPiece : Maybe TetrominoType
    , hasSwappedThisTurn : Bool
    , highScore : Int
    , combo : Int
    , statistics : Statistics
    }

type GameState
    = Playing
    | Paused
    | GameOver

type alias Board =
    List (List Cell)

type Cell
    = Empty
    | Filled Color

type alias Piece =
    { shape : List Position
    , position : Position
    , tetrominoType : TetrominoType
    , color : Color
    , rotation : Int
    , visualRotation : Float
    }

type alias Position =
    { x : Int
    , y : Int
    }

type TetrominoType
    = I | O | T | S | Z | J | L

type Color
    = Cyan | Yellow | Purple | Green | Red | Blue | Orange

type alias Statistics =
    { iPieces : Int
    , oPieces : Int
    , tPieces : Int
    , sPieces : Int
    , zPieces : Int
    , jPieces : Int
    , lPieces : Int
    }

boardWidth : Int
boardWidth = 10

boardHeight : Int
boardHeight = 20


-- TETROMINO SHAPES

getTetrominoShape : TetrominoType -> List Position
getTetrominoShape tetrominoType =
    case tetrominoType of
        I ->
            [ { x = 0, y = 1 }, { x = 1, y = 1 }, { x = 2, y = 1 }, { x = 3, y = 1 } ]
        O ->
            [ { x = 0, y = 0 }, { x = 1, y = 0 }, { x = 0, y = 1 }, { x = 1, y = 1 } ]
        T ->
            [ { x = 1, y = 0 }, { x = 0, y = 1 }, { x = 1, y = 1 }, { x = 2, y = 1 } ]
        S ->
            [ { x = 1, y = 0 }, { x = 2, y = 0 }, { x = 0, y = 1 }, { x = 1, y = 1 } ]
        Z ->
            [ { x = 0, y = 0 }, { x = 1, y = 0 }, { x = 1, y = 1 }, { x = 2, y = 1 } ]
        J ->
            [ { x = 0, y = 0 }, { x = 0, y = 1 }, { x = 1, y = 1 }, { x = 2, y = 1 } ]
        L ->
            [ { x = 2, y = 0 }, { x = 0, y = 1 }, { x = 1, y = 1 }, { x = 2, y = 1 } ]

getTetrominoColor : TetrominoType -> Color
getTetrominoColor tetrominoType =
    case tetrominoType of
        I -> Cyan
        O -> Yellow
        T -> Purple
        S -> Green
        Z -> Red
        J -> Blue
        L -> Orange


-- INIT

init : () -> ( Model, Cmd Msg )
init _ =
    ( { board = emptyBoard
      , currentPiece = Nothing
      , nextPieces = [ I, O, T ]
      , score = 0
      , level = 1
      , linesCleared = 0
      , gameState = Playing
      , dropSpeed = 1000
      , clearingRows = []
      , animationFrame = 0
      , lastSound = ""
      , heldPiece = Nothing
      , hasSwappedThisTurn = False
      , highScore = 0
      , combo = 0
      , statistics = { iPieces = 0, oPieces = 0, tPieces = 0, sPieces = 0, zPieces = 0, jPieces = 0, lPieces = 0 }
      }
    , Cmd.batch
        [ Random.generate NewPiece randomTetromino
        , Random.generate NewPiece randomTetromino
        , Random.generate NewPiece randomTetromino
        ]
    )

emptyBoard : Board
emptyBoard =
    List.repeat boardHeight (List.repeat boardWidth Empty)

randomTetromino : Random.Generator TetrominoType
randomTetromino =
    Random.uniform I [ O, T, S, Z, J, L ]


-- UPDATE

type Msg
    = Tick Time.Posix
    | AnimationTick Time.Posix
    | NewPiece TetrominoType
    | MoveLeft
    | MoveRight
    | MoveDown
    | Rotate
    | Drop
    | TogglePause
    | Restart
    | CompleteClearAnimation
    | HoldPiece

update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Tick _ ->
            if model.gameState == Playing then
                moveDown model
            else
                ( model, Cmd.none )

        AnimationTick _ ->
            -- Update visual rotation animation
            case model.currentPiece of
                Just piece ->
                    let
                        targetRotation = toFloat piece.rotation * 90
                        currentRotation = piece.visualRotation
                        diff = targetRotation - currentRotation
                        newRotation = 
                            if abs diff < 5 then
                                targetRotation
                            else
                                currentRotation + diff * 0.3
                        
                        updatedPiece = { piece | visualRotation = newRotation }
                    in
                    ( { model | currentPiece = Just updatedPiece }, Cmd.none )
                
                Nothing ->
                    ( model, Cmd.none )

        NewPiece tetrominoType ->
            case model.currentPiece of
                Nothing ->
                    -- First piece or after a piece locks
                    let
                        nextPiece = List.head model.nextPieces |> Maybe.withDefault I
                        piece = createPiece nextPiece
                        remainingPieces = List.drop 1 model.nextPieces
                        updatedPieces = remainingPieces ++ [ tetrominoType ]
                        updatedStats = incrementStatistics nextPiece model.statistics
                    in
                    if canPlacePiece piece model.board then
                        ( { model 
                          | currentPiece = Just piece
                          , nextPieces = updatedPieces
                          , hasSwappedThisTurn = False
                          , statistics = updatedStats
                          }
                        , Cmd.none
                        )
                    else
                        -- Game over - can't place new piece
                        let
                            newHighScore = max model.score model.highScore
                        in
                        ( { model | gameState = GameOver, highScore = newHighScore }, Cmd.none )

                Just _ ->
                    -- Add to end of next pieces queue
                    ( { model | nextPieces = model.nextPieces ++ [ tetrominoType ] }, Cmd.none )

        MoveLeft ->
            if model.gameState == Playing then
                let
                    newModel = movePiece { x = -1, y = 0 } model
                in
                ( if newModel /= model then { newModel | lastSound = "move" } else newModel
                , Cmd.none 
                )
            else
                ( model, Cmd.none )

        MoveRight ->
            if model.gameState == Playing then
                let
                    newModel = movePiece { x = 1, y = 0 } model
                in
                ( if newModel /= model then { newModel | lastSound = "move" } else newModel
                , Cmd.none 
                )
            else
                ( model, Cmd.none )

        MoveDown ->
            if model.gameState == Playing then
                moveDown model
            else
                ( model, Cmd.none )

        Rotate ->
            if model.gameState == Playing then
                ( rotatePiece model, Cmd.none )
            else
                ( model, Cmd.none )

        Drop ->
            if model.gameState == Playing then
                hardDrop model
            else
                ( model, Cmd.none )

        TogglePause ->
            case model.gameState of
                Playing ->
                    ( { model | gameState = Paused }, Cmd.none )
                Paused ->
                    ( { model | gameState = Playing }, Cmd.none )
                GameOver ->
                    ( model, Cmd.none )

        Restart ->
            init ()

        HoldPiece ->
            if model.gameState == Playing && not model.hasSwappedThisTurn then
                holdCurrentPiece model
            else
                ( model, Cmd.none )

        CompleteClearAnimation ->
            let
                ( clearedBoard, linesCleared ) =
                    clearLines model.board

                newLinesCleared =
                    model.linesCleared + linesCleared

                -- Combo system: increment combo if lines were cleared, reset if not
                newCombo =
                    if linesCleared > 0 then
                        model.combo + 1
                    else
                        0

                -- Bonus score for combo
                comboBonus =
                    if newCombo > 1 then
                        50 * model.level * (newCombo - 1)
                    else
                        0

                baseScore = scoreForLines linesCleared model.level

                newScore =
                    model.score + baseScore + comboBonus

                newLevel =
                    1 + (newLinesCleared // 10)

                newDropSpeed =
                    max 100 (1000 - toFloat (newLevel - 1) * 75)

                newHighScore = max newScore model.highScore
            in
            ( { model
                | board = clearedBoard
                , clearingRows = []
                , score = newScore
                , level = newLevel
                , linesCleared = newLinesCleared
                , dropSpeed = newDropSpeed
                , combo = newCombo
                , highScore = newHighScore
              }
            , Random.generate NewPiece randomTetromino
            )

createPiece : TetrominoType -> Piece
createPiece tetrominoType =
    { shape = getTetrominoShape tetrominoType
    , position = { x = 3, y = 0 }
    , tetrominoType = tetrominoType
    , color = getTetrominoColor tetrominoType
    , rotation = 0
    , visualRotation = 0
    }

movePiece : Position -> Model -> Model
movePiece offset model =
    case model.currentPiece of
        Nothing ->
            model

        Just piece ->
            let
                newPiece =
                    { piece | position = { x = piece.position.x + offset.x, y = piece.position.y + offset.y } }
            in
            if canPlacePiece newPiece model.board then
                { model | currentPiece = Just newPiece }
            else
                model

moveDown : Model -> ( Model, Cmd Msg )
moveDown model =
    case model.currentPiece of
        Nothing ->
            ( model, Random.generate NewPiece randomTetromino )

        Just piece ->
            let
                newPiece =
                    { piece | position = { x = piece.position.x, y = piece.position.y + 1 } }
            in
            if canPlacePiece newPiece model.board then
                ( { model | currentPiece = Just newPiece }, Cmd.none )
            else
                -- Lock piece and check for line clears
                lockPiece model

lockPiece : Model -> ( Model, Cmd Msg )
lockPiece model =
    case model.currentPiece of
        Nothing ->
            ( model, Cmd.none )

        Just piece ->
            let
                newBoard =
                    placePieceOnBoard piece model.board

                rowsToClear =
                    getRowsToClear newBoard

                linesCleared =
                    List.length rowsToClear
            in
            if linesCleared > 0 then
                -- Show clearing animation first
                ( { model 
                    | board = newBoard
                    , currentPiece = Nothing
                    , clearingRows = rowsToClear
                    , lastSound = "clear"
                  }
                , Task.perform (\_ -> CompleteClearAnimation) (Process.sleep 400)
                )
            else
                -- No lines to clear, spawn next piece immediately
                ( { model 
                    | board = newBoard
                    , currentPiece = Nothing
                    , lastSound = "lock"
                  }
                , Random.generate NewPiece randomTetromino
                )

getRowsToClear : Board -> List Int
getRowsToClear board =
    board
        |> List.indexedMap (\index row -> 
            if isLineFull row then
                Just index
            else
                Nothing
        )
        |> List.filterMap identity

scoreForLines : Int -> Int -> Int
scoreForLines lines level =
    case lines of
        1 -> 40 * level
        2 -> 100 * level
        3 -> 300 * level
        4 -> 1200 * level
        _ -> 0

hardDrop : Model -> ( Model, Cmd Msg )
hardDrop model =
    case model.currentPiece of
        Nothing ->
            ( model, Cmd.none )

        Just piece ->
            let
                droppedPiece =
                    dropPieceToBottom piece model.board
                
                dropDistance =
                    droppedPiece.position.y - piece.position.y
                
                newScore =
                    model.score + (dropDistance * 2)
            in
            lockPiece { model | currentPiece = Just droppedPiece, score = newScore }

dropPieceToBottom : Piece -> Board -> Piece
dropPieceToBottom piece board =
    let
        nextPiece =
            { piece | position = { x = piece.position.x, y = piece.position.y + 1 } }
    in
    if canPlacePiece nextPiece board then
        dropPieceToBottom nextPiece board
    else
        piece

rotatePiece : Model -> Model
rotatePiece model =
    case model.currentPiece of
        Nothing ->
            model

        Just piece ->
            let
                rotatedShape =
                    rotateShape piece.shape

                rotatedPiece =
                    { piece 
                    | shape = rotatedShape
                    , rotation = piece.rotation + 1
                    , visualRotation = toFloat (piece.rotation + 1) * 90
                    }
            in
            if canPlacePiece rotatedPiece model.board then
                { model | currentPiece = Just rotatedPiece, lastSound = "rotate" }
            else
                -- Try wall kicks
                tryWallKicks rotatedPiece model

tryWallKicks : Piece -> Model -> Model
tryWallKicks piece model =
    let
        offsets = [ { x = 1, y = 0 }, { x = -1, y = 0 }, { x = 2, y = 0 }, { x = -2, y = 0 } ]
        
        tryOffset offset =
            let
                kickedPiece =
                    { piece | position = { x = piece.position.x + offset.x, y = piece.position.y + offset.y } }
            in
            if canPlacePiece kickedPiece model.board then
                Just kickedPiece
            else
                Nothing
    in
    case List.filterMap tryOffset offsets |> List.head of
        Just kickedPiece ->
            { model | currentPiece = Just kickedPiece, lastSound = "rotate" }
        
        Nothing ->
            model

rotateShape : List Position -> List Position
rotateShape shape =
    -- Rotate 90 degrees clockwise: (x, y) -> (y, -x)
    -- Then normalize to keep shape in positive coordinates
    let
        rotated =
            List.map (\pos -> { x = pos.y, y = -pos.x }) shape

        minX =
            List.map .x rotated |> List.minimum |> Maybe.withDefault 0

        minY =
            List.map .y rotated |> List.minimum |> Maybe.withDefault 0
    in
    List.map (\pos -> { x = pos.x - minX, y = pos.y - minY }) rotated

canPlacePiece : Piece -> Board -> Bool
canPlacePiece piece board =
    List.all (isValidPosition board) (getPiecePositions piece)

getPiecePositions : Piece -> List Position
getPiecePositions piece =
    List.map (\offset -> { x = piece.position.x + offset.x, y = piece.position.y + offset.y }) piece.shape

isValidPosition : Board -> Position -> Bool
isValidPosition board pos =
    pos.x >= 0 && pos.x < boardWidth && pos.y >= 0 && pos.y < boardHeight &&
    (getCellAt pos board == Empty)

getCellAt : Position -> Board -> Cell
getCellAt pos board =
    board
        |> List.drop pos.y
        |> List.head
        |> Maybe.withDefault []
        |> List.drop pos.x
        |> List.head
        |> Maybe.withDefault Empty

placePieceOnBoard : Piece -> Board -> Board
placePieceOnBoard piece board =
    let
        positions =
            getPiecePositions piece

        updateCell : Position -> Board -> Board
        updateCell pos brd =
            List.indexedMap
                (\y row ->
                    if y == pos.y then
                        List.indexedMap
                            (\x cell ->
                                if x == pos.x then
                                    Filled piece.color
                                else
                                    cell
                            )
                            row
                    else
                        row
                )
                brd
    in
    List.foldl updateCell board positions

clearLines : Board -> ( Board, Int )
clearLines board =
    let
        ( remainingRows, clearedCount ) =
            board
                |> List.foldl
                    (\row ( rows, count ) ->
                        if isLineFull row then
                            ( rows, count + 1 )
                        else
                            ( row :: rows, count )
                    )
                    ( [], 0 )

        newRows =
            List.repeat clearedCount (List.repeat boardWidth Empty)
    in
    ( newRows ++ List.reverse remainingRows, clearedCount )

isLineFull : List Cell -> Bool
isLineFull row =
    List.all (\cell -> cell /= Empty) row


-- HOLD PIECE

holdCurrentPiece : Model -> ( Model, Cmd Msg )
holdCurrentPiece model =
    case model.currentPiece of
        Nothing ->
            ( model, Cmd.none )

        Just currentPiece ->
            case model.heldPiece of
                Nothing ->
                    -- First time holding - store current piece and spawn next
                    ( { model 
                        | heldPiece = Just currentPiece.tetrominoType
                        , currentPiece = Nothing
                        , hasSwappedThisTurn = True
                      }
                    , Random.generate NewPiece randomTetromino
                    )

                Just heldType ->
                    -- Swap current with held
                    let
                        newPiece = createPiece heldType
                    in
                    if canPlacePiece newPiece model.board then
                        ( { model 
                            | heldPiece = Just currentPiece.tetrominoType
                            , currentPiece = Just newPiece
                            , hasSwappedThisTurn = True
                          }
                        , Cmd.none
                        )
                    else
                        -- Can't place held piece, don't swap
                        ( model, Cmd.none )


-- STATISTICS

incrementStatistics : TetrominoType -> Statistics -> Statistics
incrementStatistics tetrominoType stats =
    case tetrominoType of
        I -> { stats | iPieces = stats.iPieces + 1 }
        O -> { stats | oPieces = stats.oPieces + 1 }
        T -> { stats | tPieces = stats.tPieces + 1 }
        S -> { stats | sPieces = stats.sPieces + 1 }
        Z -> { stats | zPieces = stats.zPieces + 1 }
        J -> { stats | jPieces = stats.jPieces + 1 }
        L -> { stats | lPieces = stats.lPieces + 1 }

getTotalPieces : Statistics -> Int
getTotalPieces stats =
    stats.iPieces + stats.oPieces + stats.tPieces + stats.sPieces + stats.zPieces + stats.jPieces + stats.lPieces


-- GHOST PIECE

getGhostPiece : Piece -> Board -> Piece
getGhostPiece piece board =
    dropPieceToBottom piece board


-- SUBSCRIPTIONS

subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ if model.gameState == Playing then
            Time.every model.dropSpeed Tick
          else
            Sub.none
        , Browser.Events.onAnimationFrame AnimationTick
        , onKeyDown keyDecoder
        ]

keyDecoder : Decode.Decoder Msg
keyDecoder =
    Decode.field "key" Decode.string
        |> Decode.andThen
            (\key ->
                case key of
                    "ArrowLeft" ->
                        Decode.succeed MoveLeft

                    "ArrowRight" ->
                        Decode.succeed MoveRight

                    "ArrowDown" ->
                        Decode.succeed MoveDown

                    "ArrowUp" ->
                        Decode.succeed Rotate

                    " " ->
                        Decode.succeed Drop

                    "p" ->
                        Decode.succeed TogglePause

                    "P" ->
                        Decode.succeed TogglePause

                    "h" ->
                        Decode.succeed HoldPiece

                    "H" ->
                        Decode.succeed HoldPiece

                    _ ->
                        Decode.fail "Not a game key"
            )


-- VIEW

view : Model -> Html Msg
view model =
    div
        [ style "font-family" "'Segoe UI', Tahoma, Geneva, Verdana, sans-serif"
        , style "display" "flex"
        , style "justify-content" "center"
        , style "align-items" "center"
        , style "min-height" "100vh"
        , style "background" "linear-gradient(135deg, #1a1a2e 0%, #16213e 50%, #0f3460 100%)"
        , style "color" "#eee"
        , attribute "data-sound" model.lastSound
        ]
        [ div
            [ style "text-align" "center" ]
            [ h1 
                [ style "color" "#00ff88"
                , style "font-size" "48px"
                , style "margin-bottom" "20px"
                , style "text-shadow" "0 0 20px rgba(0, 255, 136, 0.5), 0 0 40px rgba(0, 255, 136, 0.3)"
                , style "letter-spacing" "8px"
                ] 
                [ text "TETRIS" ]
            , div
                [ style "display" "flex"
                , style "gap" "20px"
                , style "justify-content" "center"
                , style "align-items" "flex-start"
                ]
                [ viewBoard model
                , viewSidebar model
                ]
            , viewControls
            , if model.gameState == GameOver then
                viewGameOver
              else if model.gameState == Paused then
                viewPaused
              else
                text ""
            ]
        ]

viewBoard : Model -> Html Msg
viewBoard model =
    let
        cellSize = 25
        boardWidthPx = toFloat boardWidth * cellSize
        boardHeightPx = toFloat boardHeight * cellSize
    in
    div
        [ style "border" "3px solid #00ff88"
        , style "background-color" "#0f0f23"
        , style "display" "inline-block"
        , style "box-shadow" "0 0 20px rgba(0, 255, 136, 0.3), inset 0 0 30px rgba(0, 0, 0, 0.5)"
        , style "border-radius" "5px"
        , style "overflow" "hidden"
        ]
        [ svg
            [ SvgAttr.width (String.fromFloat boardWidthPx)
            , SvgAttr.height (String.fromFloat boardHeightPx)
            , SvgAttr.viewBox ("0 0 " ++ String.fromFloat boardWidthPx ++ " " ++ String.fromFloat boardHeightPx)
            ]
            [ -- Draw locked cells
              g [] (viewLockedCells model.board model.clearingRows cellSize)
            -- Draw ghost piece (preview of where piece will land)
            , case model.currentPiece of
                Just piece ->
                    let
                        ghostPiece = getGhostPiece piece model.board
                    in
                    if ghostPiece.position.y /= piece.position.y then
                        viewGhostPieceSVG ghostPiece cellSize
                    else
                        g [] []
                
                Nothing ->
                    g [] []
            -- Draw current piece with rotation
            , case model.currentPiece of
                Just piece ->
                    viewPieceSVG piece cellSize
                
                Nothing ->
                    g [] []
            ]
        ]

viewLockedCells : Board -> List Int -> Float -> List (Svg Msg)
viewLockedCells board clearingRows cellSize =
    board
        |> List.indexedMap (\y row ->
            row
                |> List.indexedMap (\x cell ->
                    let
                        isClearing = List.member y clearingRows
                    in
                    case cell of
                        Empty ->
                            rect
                                [ SvgAttr.x (String.fromFloat (toFloat x * cellSize))
                                , SvgAttr.y (String.fromFloat (toFloat y * cellSize))
                                , SvgAttr.width (String.fromFloat cellSize)
                                , SvgAttr.height (String.fromFloat cellSize)
                                , SvgAttr.fill "#0f0f23"
                                , SvgAttr.stroke "#16213e"
                                , SvgAttr.strokeWidth "1"
                                ]
                                []
                        
                        Filled color ->
                            if isClearing then
                                rect
                                    [ SvgAttr.x (String.fromFloat (toFloat x * cellSize))
                                    , SvgAttr.y (String.fromFloat (toFloat y * cellSize))
                                    , SvgAttr.width (String.fromFloat cellSize)
                                    , SvgAttr.height (String.fromFloat cellSize)
                                    , SvgAttr.fill "#ffffff"
                                    , SvgAttr.stroke "#ffff00"
                                    , SvgAttr.strokeWidth "2"
                                    , SvgAttr.rx "2"
                                    , SvgAttr.class "clearing-cell"
                                    ]
                                    []
                            else
                                rect
                                    [ SvgAttr.x (String.fromFloat (toFloat x * cellSize + 1))
                                    , SvgAttr.y (String.fromFloat (toFloat y * cellSize + 1))
                                    , SvgAttr.width (String.fromFloat (cellSize - 2))
                                    , SvgAttr.height (String.fromFloat (cellSize - 2))
                                    , SvgAttr.fill (colorToString color)
                                    , SvgAttr.stroke (colorToLightString color)
                                    , SvgAttr.strokeWidth "1.5"
                                    , SvgAttr.rx "2"
                                    , SvgAttr.filter "url(#glow)"
                                    ]
                                    []
                )
        )
        |> List.concat

viewPieceSVG : Piece -> Float -> Svg Msg
viewPieceSVG piece cellSize =
    let
        centerX = toFloat piece.position.x * cellSize + cellSize * 1.5
        centerY = toFloat piece.position.y * cellSize + cellSize * 1.5
        
        positions = getPiecePositions piece
    in
    g 
        [ SvgAttr.transform 
            ("rotate(" ++ String.fromFloat piece.visualRotation 
            ++ " " ++ String.fromFloat centerX 
            ++ " " ++ String.fromFloat centerY ++ ")")
        , SvgAttr.style "transition: transform 0.2s ease-out"
        ]
        (List.map (viewPieceCell piece.color cellSize) positions)

viewPieceCell : Color -> Float -> Position -> Svg Msg
viewPieceCell color cellSize pos =
    rect
        [ SvgAttr.x (String.fromFloat (toFloat pos.x * cellSize + 1))
        , SvgAttr.y (String.fromFloat (toFloat pos.y * cellSize + 1))
        , SvgAttr.width (String.fromFloat (cellSize - 2))
        , SvgAttr.height (String.fromFloat (cellSize - 2))
        , SvgAttr.fill (colorToString color)
        , SvgAttr.stroke (colorToLightString color)
        , SvgAttr.strokeWidth "1.5"
        , SvgAttr.rx "2"
        , SvgAttr.filter "url(#glow)"
        ]
        []

viewGhostPieceSVG : Piece -> Float -> Svg Msg
viewGhostPieceSVG piece cellSize =
    let
        positions = getPiecePositions piece
    in
    g []
        (List.map (viewGhostPieceCell piece.color cellSize) positions)

viewGhostPieceCell : Color -> Float -> Position -> Svg Msg
viewGhostPieceCell color cellSize pos =
    rect
        [ SvgAttr.x (String.fromFloat (toFloat pos.x * cellSize + 1))
        , SvgAttr.y (String.fromFloat (toFloat pos.y * cellSize + 1))
        , SvgAttr.width (String.fromFloat (cellSize - 2))
        , SvgAttr.height (String.fromFloat (cellSize - 2))
        , SvgAttr.fill "none"
        , SvgAttr.stroke (colorToLightString color)
        , SvgAttr.strokeWidth "2"
        , SvgAttr.strokeDasharray "4,4"
        , SvgAttr.rx "2"
        , SvgAttr.opacity "0.4"
        ]
        []

viewCell : Cell -> Html Msg
viewCell cell =
    let
        (bgColor, borderColor, boxShadow) =
            case cell of
                Empty ->
                    ("#0f0f23", "#16213e", "inset 0 0 5px rgba(0,0,0,0.3)")

                Filled c ->
                    let
                        color = colorToString c
                        lightColor = colorToLightString c
                    in
                    (color, lightColor, "0 0 8px " ++ color ++ "80")
    in
    div
        [ style "width" "25px"
        , style "height" "25px"
        , style "border" ("1px solid " ++ borderColor)
        , style "background" bgColor
        , style "box-sizing" "border-box"
        , style "box-shadow" boxShadow
        , style "transition" "all 0.15s ease"
        , style "border-radius" "2px"
        ]
        []

colorToString : Color -> String
colorToString color =
    case color of
        Cyan -> "#00f5ff"
        Yellow -> "#ffed00"
        Purple -> "#b026ff"
        Green -> "#00ff00"
        Red -> "#ff0000"
        Blue -> "#0000ff"
        Orange -> "#ff8800"

colorToLightString : Color -> String
colorToLightString color =
    case color of
        Cyan -> "#66f8ff"
        Yellow -> "#fff366"
        Purple -> "#d266ff"
        Green -> "#66ff66"
        Red -> "#ff6666"
        Blue -> "#6666ff"
        Orange -> "#ffaa66"

viewSidebar : Model -> Html Msg
viewSidebar model =
    div
        [ style "text-align" "left"
        , style "min-width" "200px"
        ]
        [ viewScoreboard model
        , viewHoldPiece model
        , viewNextPiece model
        , viewStatistics model
        ]

viewScoreboard : Model -> Html Msg
viewScoreboard model =
    div
        [ style "background" "linear-gradient(135deg, #16213e 0%, #1a2847 100%)"
        , style "padding" "15px"
        , style "border-radius" "8px"
        , style "margin-bottom" "20px"
        , style "box-shadow" "0 4px 15px rgba(0, 0, 0, 0.3)"
        , style "border" "1px solid #2a3a5e"
        ]
        [ h2 [ style "margin-top" "0", style "color" "#00ff88", style "text-shadow" "0 0 10px rgba(0, 255, 136, 0.5)" ] [ text "Score" ]
        , p [ style "font-size" "28px", style "margin" "10px 0", style "font-weight" "bold", style "color" "#00ff88" ] [ text (String.fromInt model.score) ]
        , if model.highScore > 0 then
            div []
                [ h2 [ style "margin-top" "15px", style "color" "#ffaa00", style "font-size" "16px", style "text-shadow" "0 0 10px rgba(255, 170, 0, 0.5)" ] [ text "High Score" ]
                , p [ style "font-size" "20px", style "margin" "5px 0", style "font-weight" "bold", style "color" "#ffaa00" ] [ text (String.fromInt model.highScore) ]
                ]
          else
            text ""
        , h2 [ style "margin-top" "15px", style "color" "#00ff88", style "text-shadow" "0 0 10px rgba(0, 255, 136, 0.5)" ] [ text "Level" ]
        , p [ style "font-size" "28px", style "margin" "10px 0", style "font-weight" "bold", style "color" "#00ff88" ] [ text (String.fromInt model.level) ]
        , h2 [ style "margin-top" "15px", style "color" "#00ff88", style "text-shadow" "0 0 10px rgba(0, 255, 136, 0.5)" ] [ text "Lines" ]
        , p [ style "font-size" "28px", style "margin" "10px 0", style "font-weight" "bold", style "color" "#00ff88" ] [ text (String.fromInt model.linesCleared) ]
        , if model.combo > 1 then
            div []
                [ h2 [ style "margin-top" "15px", style "color" "#ff00ff", style "font-size" "16px", style "text-shadow" "0 0 10px rgba(255, 0, 255, 0.5)" ] [ text "Combo!" ]
                , p [ style "font-size" "24px", style "margin" "5px 0", style "font-weight" "bold", style "color" "#ff00ff" ] [ text (String.fromInt model.combo ++ "x") ]
                ]
          else
            text ""
        ]

viewHoldPiece : Model -> Html Msg
viewHoldPiece model =
    div
        [ style "background" "linear-gradient(135deg, #16213e 0%, #1a2847 100%)"
        , style "padding" "15px"
        , style "border-radius" "8px"
        , style "margin-bottom" "20px"
        , style "box-shadow" "0 4px 15px rgba(0, 0, 0, 0.3)"
        , style "border" "1px solid #2a3a5e"
        ]
        [ h2 [ style "margin-top" "0", style "color" "#00ff88", style "text-shadow" "0 0 10px rgba(0, 255, 136, 0.5)" ] [ text "Hold (H)" ]
        , div
            [ style "background-color" "#0f0f23"
            , style "padding" "8px"
            , style "border-radius" "5px"
            , style "border" "2px solid #00ff88"
            , style "min-height" "60px"
            , style "display" "flex"
            , style "align-items" "center"
            , style "justify-content" "center"
            ]
            [ case model.heldPiece of
                Just tetrominoType ->
                    viewTetromino tetrominoType
                
                Nothing ->
                    p [ style "color" "#555", style "margin" "0", style "font-size" "12px" ] [ text "Empty" ]
            ]
        ]

viewNextPiece : Model -> Html Msg
viewNextPiece model =
    div
        [ style "background" "linear-gradient(135deg, #16213e 0%, #1a2847 100%)"
        , style "padding" "15px"
        , style "border-radius" "8px"
        , style "box-shadow" "0 4px 15px rgba(0, 0, 0, 0.3)"
        , style "border" "1px solid #2a3a5e"
        ]
        [ h2 [ style "margin-top" "0", style "color" "#00ff88", style "text-shadow" "0 0 10px rgba(0, 255, 136, 0.5)" ] [ text "Next Pieces" ]
        , div
            [ style "display" "flex"
            , style "flex-direction" "column"
            , style "gap" "10px"
            ]
            (List.indexedMap viewNextPiecePreview (List.take 3 model.nextPieces))
        ]

viewNextPiecePreview : Int -> TetrominoType -> Html Msg
viewNextPiecePreview index tetrominoType =
    let
        opacity = String.fromFloat (1.0 - (toFloat index * 0.25))
        scale = String.fromFloat (1.0 - (toFloat index * 0.1))
    in
    div
        [ style "background-color" "#0f0f23"
        , style "padding" "8px"
        , style "border-radius" "5px"
        , style "border" (if index == 0 then "2px solid #00ff88" else "2px solid #2a2a4e")
        , style "transition" "all 0.3s ease"
        , style "opacity" opacity
        , style "transform" ("scale(" ++ scale ++ ")")
        , style "box-shadow" (if index == 0 then "0 0 15px rgba(0, 255, 136, 0.3)" else "0 2px 8px rgba(0, 0, 0, 0.2)")
        ]
        [ viewTetromino tetrominoType ]

viewTetromino : TetrominoType -> Html Msg
viewTetromino tetrominoType =
    let
        shape = getTetrominoShape tetrominoType
        color = getTetrominoColor tetrominoType
        
        maxX = List.map .x shape |> List.maximum |> Maybe.withDefault 0
        maxY = List.map .y shape |> List.maximum |> Maybe.withDefault 0
        
        grid = List.range 0 maxY
            |> List.map (\y ->
                List.range 0 maxX
                    |> List.map (\x ->
                        if List.any (\pos -> pos.x == x && pos.y == y) shape then
                            Filled color
                        else
                            Empty
                    )
                )
    in
    div []
        (List.map viewRowSimple grid)

viewRowSimple : List Cell -> Html Msg
viewRowSimple row =
    div
        [ style "display" "flex" ]
        (List.map viewCell row)

viewStatistics : Model -> Html Msg
viewStatistics model =
    let
        stats = model.statistics
        total = getTotalPieces stats
    in
    if total == 0 then
        text ""
    else
        div
            [ style "background" "linear-gradient(135deg, #16213e 0%, #1a2847 100%)"
            , style "padding" "15px"
            , style "border-radius" "8px"
            , style "margin-top" "20px"
            , style "box-shadow" "0 4px 15px rgba(0, 0, 0, 0.3)"
            , style "border" "1px solid #2a3a5e"
            ]
            [ h2 [ style "margin-top" "0", style "color" "#00ff88", style "font-size" "16px", style "text-shadow" "0 0 10px rgba(0, 255, 136, 0.5)" ] [ text "Statistics" ]
            , viewStatRow "I" stats.iPieces Cyan
            , viewStatRow "O" stats.oPieces Yellow
            , viewStatRow "T" stats.tPieces Purple
            , viewStatRow "S" stats.sPieces Green
            , viewStatRow "Z" stats.zPieces Red
            , viewStatRow "J" stats.jPieces Blue
            , viewStatRow "L" stats.lPieces Orange
            ]

viewStatRow : String -> Int -> Color -> Html Msg
viewStatRow name count color =
    div
        [ style "display" "flex"
        , style "justify-content" "space-between"
        , style "align-items" "center"
        , style "margin" "5px 0"
        , style "padding" "3px"
        ]
        [ div
            [ style "display" "flex"
            , style "align-items" "center"
            , style "gap" "8px"
            ]
            [ div
                [ style "width" "20px"
                , style "height" "20px"
                , style "background" (colorToString color)
                , style "border" ("1px solid " ++ colorToLightString color)
                , style "border-radius" "2px"
                ]
                []
            , p [ style "margin" "0", style "color" "#ccc", style "font-size" "14px" ] [ text name ]
            ]
        , p [ style "margin" "0", style "color" "#00ff88", style "font-weight" "bold", style "font-size" "14px" ] [ text (String.fromInt count) ]
        ]

viewControls : Html Msg
viewControls =
    div
        [ style "margin-top" "20px"
        , style "background" "linear-gradient(135deg, #16213e 0%, #1a2847 100%)"
        , style "padding" "15px"
        , style "border-radius" "8px"
        , style "max-width" "500px"
        , style "margin-left" "auto"
        , style "margin-right" "auto"
        , style "box-shadow" "0 4px 15px rgba(0, 0, 0, 0.3)"
        , style "border" "1px solid #2a3a5e"
        ]
        [ h2 [ style "color" "#00ff88", style "margin-top" "0", style "text-shadow" "0 0 10px rgba(0, 255, 136, 0.5)" ] [ text "Controls" ]
        , p [ style "margin" "8px 0" ] [ text "← → : Move Left/Right" ]
        , p [ style "margin" "8px 0" ] [ text "↓ : Move Down" ]
        , p [ style "margin" "8px 0" ] [ text "↑ : Rotate" ]
        , p [ style "margin" "8px 0" ] [ text "Space : Hard Drop" ]
        , p [ style "margin" "8px 0" ] [ text "H : Hold Piece" ]
        , p [ style "margin" "8px 0" ] [ text "P : Pause" ]
        , button
            [ onClick Restart
            , style "margin-top" "10px"
            , style "padding" "10px 20px"
            , style "font-size" "16px"
            , style "background" "linear-gradient(135deg, #00ff88 0%, #00cc6a 100%)"
            , style "color" "#0f0f23"
            , style "border" "none"
            , style "border-radius" "5px"
            , style "cursor" "pointer"
            , style "font-weight" "bold"
            , style "box-shadow" "0 4px 10px rgba(0, 255, 136, 0.3)"
            , style "transition" "all 0.3s ease"
            ]
            [ text "New Game" ]
        ]

viewGameOver : Html Msg
viewGameOver =
    div
        [ style "position" "fixed"
        , style "top" "50%"
        , style "left" "50%"
        , style "transform" "translate(-50%, -50%)"
        , style "background" "linear-gradient(135deg, #16213e 0%, #1a2847 100%)"
        , style "padding" "40px"
        , style "border-radius" "15px"
        , style "border" "3px solid #ff0000"
        , style "z-index" "100"
        , style "box-shadow" "0 0 30px rgba(255, 0, 0, 0.5), 0 10px 50px rgba(0, 0, 0, 0.8)"
        ]
        [ h1 
            [ style "color" "#ff0000"
            , style "margin-top" "0"
            , style "text-shadow" "0 0 20px rgba(255, 0, 0, 0.8)"
            , style "font-size" "36px"
            ] 
            [ text "GAME OVER" ]
        , button
            [ onClick Restart
            , style "padding" "15px 30px"
            , style "font-size" "18px"
            , style "background" "linear-gradient(135deg, #00ff88 0%, #00cc6a 100%)"
            , style "color" "#0f0f23"
            , style "border" "none"
            , style "border-radius" "8px"
            , style "cursor" "pointer"
            , style "font-weight" "bold"
            , style "box-shadow" "0 4px 15px rgba(0, 255, 136, 0.4)"
            , style "transition" "all 0.3s ease"
            ]
            [ text "Play Again" ]
        ]

viewPaused : Html Msg
viewPaused =
    div
        [ style "position" "fixed"
        , style "top" "50%"
        , style "left" "50%"
        , style "transform" "translate(-50%, -50%)"
        , style "background" "linear-gradient(135deg, #16213e 0%, #1a2847 100%)"
        , style "padding" "40px"
        , style "border-radius" "15px"
        , style "border" "3px solid #00ff88"
        , style "z-index" "100"
        , style "box-shadow" "0 0 30px rgba(0, 255, 136, 0.5), 0 10px 50px rgba(0, 0, 0, 0.8)"
        ]
        [ h1 
            [ style "color" "#00ff88"
            , style "margin-top" "0"
            , style "text-shadow" "0 0 20px rgba(0, 255, 136, 0.8)"
            , style "font-size" "36px"
            ] 
            [ text "PAUSED" ]
        , p 
            [ style "font-size" "18px"
            , style "color" "#cccccc"
            ] 
            [ text "Press P to continue" ]
        ]
