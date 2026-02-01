# Tetris - Pure Elm Implementation

A fully playable Tetris game built with Elm 0.19.1. Features standard tetromino pieces, rotation, collision detection, line clearing, levels, and scoring.

## Features

- **Classic Tetris Gameplay**: All 7 standard tetrominoes (I, O, T, S, Z, J, L)
- **Rotation System**: Piece rotation with wall kick support
- **Collision Detection**: Proper collision handling for board boundaries and other pieces
- **Line Clearing**: Clear complete lines and earn points
- **Progressive Difficulty**: Speed increases every 10 lines cleared
- **Scoring System**: Points awarded for lines cleared and hard drops
- **Next Piece Preview**: See the next piece coming
- **Game States**: Playing, Paused, and Game Over states
- **Responsive Controls**: Keyboard controls for all actions

## Requirements

- [Elm](https://elm-lang.org/) 0.19.1 or later
- A modern web browser

## Installation

1. Install Elm if you haven't already:
   ```bash
   npm install -g elm
   ```

2. Clone this repository:
   ```bash
   git clone https://github.com/mk43v3r/AISlopTetris.git
   cd AISlopTetris
   ```

## Building the Game

Run the build script:
```bash
./build.sh
```

Or manually compile with:
```bash
elm make src/Main.elm --output=main.js --optimize
```

## Running the Game

After building, simply open `index.html` in your web browser:
```bash
# On macOS
open index.html

# On Linux
xdg-open index.html

# On Windows
start index.html
```

Or use a local web server:
```bash
# Python 3
python -m http.server 8000

# Python 2
python -m SimpleHTTPServer 8000

# Node.js (if you have http-server installed)
npx http-server
```

Then navigate to `http://localhost:8000` in your browser.

## Controls

- **← / →** : Move piece left/right
- **↓** : Move piece down faster (soft drop)
- **↑** : Rotate piece clockwise
- **Space** : Hard drop (instantly drop to bottom)
- **P** : Pause/unpause game

## Game Rules

- **Scoring**:
  - 1 line: 40 × level
  - 2 lines: 100 × level
  - 3 lines: 300 × level
  - 4 lines (Tetris): 1200 × level
  - Hard drop: 2 points per row dropped

- **Levels**: Level increases every 10 lines cleared
- **Speed**: Drop speed increases by 100ms per level (minimum 100ms)
- **Game Over**: Game ends when a new piece cannot be placed at the top

## Project Structure

```
AISlopTetris/
├── src/
│   └── Main.elm          # Main game logic and UI
├── elm.json              # Elm dependencies configuration
├── index.html            # HTML wrapper for the app
├── build.sh              # Build script
└── README.md             # This file
```

## Development

To work on the game:

1. Make changes to `src/Main.elm`
2. Rebuild with `./build.sh` or `elm make src/Main.elm --output=main.js`
3. Refresh your browser to see changes

For development with live reload, you can use:
```bash
elm reactor
```
Then navigate to `http://localhost:8000` and open `src/Main.elm`.

## Technologies Used

- **Elm 0.19.1**: Functional programming language for the web
- **elm/browser**: For creating browser applications
- **elm/html**: For HTML generation
- **elm/time**: For game timing
- **elm/random**: For random tetromino generation

## License

This project was created using AI assistance.

## Credits

Built as a demonstration of pure Elm architecture for game development.
