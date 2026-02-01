module Main exposing (main)

import Browser
import Browser.Events exposing (onKeyDown)
import Html exposing (Html, div, h1, h2, p, text, button)
import Html.Attributes exposing (style, class)
import Html.Events exposing (onClick)
import Json.Decode as Decode
import Random
import Time
import Task
import Process


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
    }

type alias Position =
    { x : Int
    , y : Int
    }

type TetrominoType
    = I | O | T | S | Z | J | L

type Color
    = Cyan | Yellow | Purple | Green | Red | Blue | Orange

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
    | NewPiece TetrominoType
    | MoveLeft
    | MoveRight
    | MoveDown
    | Rotate
    | Drop
    | TogglePause
    | Restart
    | CompleteClearAnimation

update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Tick _ ->
            if model.gameState == Playing then
                moveDown model
            else
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
                    in
                    if canPlacePiece piece model.board then
                        ( { model 
                          | currentPiece = Just piece
                          , nextPieces = updatedPieces
                          }
                        , Cmd.none
                        )
                    else
                        -- Game over - can't place new piece
                        ( { model | gameState = GameOver }, Cmd.none )

                Just _ ->
                    -- Add to end of next pieces queue
                    ( { model | nextPieces = model.nextPieces ++ [ tetrominoType ] }, Cmd.none )

        MoveLeft ->
            if model.gameState == Playing then
                ( movePiece { x = -1, y = 0 } model, Cmd.none )
            else
                ( model, Cmd.none )

        MoveRight ->
            if model.gameState == Playing then
                ( movePiece { x = 1, y = 0 } model, Cmd.none )
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

        CompleteClearAnimation ->
            let
                ( clearedBoard, linesCleared ) =
                    clearLines model.board

                newLinesCleared =
                    model.linesCleared + linesCleared

                newScore =
                    model.score + scoreForLines linesCleared model.level

                newLevel =
                    1 + (newLinesCleared // 10)

                newDropSpeed =
                    max 100 (1000 - toFloat (newLevel - 1) * 75)
            in
            ( { model
                | board = clearedBoard
                , clearingRows = []
                , score = newScore
                , level = newLevel
                , linesCleared = newLinesCleared
                , dropSpeed = newDropSpeed
              }
            , Random.generate NewPiece randomTetromino
            )

createPiece : TetrominoType -> Piece
createPiece tetrominoType =
    { shape = getTetrominoShape tetrominoType
    , position = { x = 3, y = 0 }
    , tetrominoType = tetrominoType
    , color = getTetrominoColor tetrominoType
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
                  }
                , Task.perform (\_ -> CompleteClearAnimation) (Process.sleep 400)
                )
            else
                -- No lines to clear, spawn next piece immediately
                ( { model 
                    | board = newBoard
                    , currentPiece = Nothing
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
                    { piece | shape = rotatedShape }
            in
            if canPlacePiece rotatedPiece model.board then
                { model | currentPiece = Just rotatedPiece }
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
            { model | currentPiece = Just kickedPiece }
        
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


-- SUBSCRIPTIONS

subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ if model.gameState == Playing then
            Time.every model.dropSpeed Tick
          else
            Sub.none
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
        boardWithPiece =
            case model.currentPiece of
                Nothing ->
                    model.board

                Just piece ->
                    renderPieceOnBoard piece model.board
    in
    div
        [ style "border" "3px solid #00ff88"
        , style "background-color" "#0f0f23"
        , style "display" "inline-block"
        , style "box-shadow" "0 0 20px rgba(0, 255, 136, 0.3), inset 0 0 30px rgba(0, 0, 0, 0.5)"
        , style "border-radius" "5px"
        ]
        (List.indexedMap (viewRowWithIndex model) boardWithPiece)

viewRowWithIndex : Model -> Int -> List Cell -> Html Msg
viewRowWithIndex model rowIndex row =
    div
        [ style "display" "flex" ]
        (List.indexedMap (viewCellInRow rowIndex model) row)

renderPieceOnBoard : Piece -> Board -> Board
renderPieceOnBoard piece board =
    let
        positions =
            getPiecePositions piece

        isPartOfPiece : Int -> Int -> Bool
        isPartOfPiece x y =
            List.any (\pos -> pos.x == x && pos.y == y) positions
    in
    List.indexedMap
        (\y row ->
            List.indexedMap
                (\x cell ->
                    if isPartOfPiece x y then
                        Filled piece.color
                    else
                        cell
                )
                row
        )
        board

viewCellInRow : Int -> Model -> Int -> Cell -> Html Msg
viewCellInRow rowIndex model colIndex cell =
    let
        isClearing = List.member rowIndex model.clearingRows
        
        (bgColor, borderColor, boxShadow) =
            if isClearing then
                -- Flash white when clearing
                ("#ffffff", "#ffff00", "0 0 20px #ffff00, inset 0 0 10px #ffffff")
            else
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
        , viewNextPiece model
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
        , h2 [ style "margin-top" "15px", style "color" "#00ff88", style "text-shadow" "0 0 10px rgba(0, 255, 136, 0.5)" ] [ text "Level" ]
        , p [ style "font-size" "28px", style "margin" "10px 0", style "font-weight" "bold", style "color" "#00ff88" ] [ text (String.fromInt model.level) ]
        , h2 [ style "margin-top" "15px", style "color" "#00ff88", style "text-shadow" "0 0 10px rgba(0, 255, 136, 0.5)" ] [ text "Lines" ]
        , p [ style "font-size" "28px", style "margin" "10px 0", style "font-weight" "bold", style "color" "#00ff88" ] [ text (String.fromInt model.linesCleared) ]
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
