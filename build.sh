#!/bin/bash
# Build script for Tetris Elm application

echo "Building Tetris Elm application..."

# Compile Elm to JavaScript
elm make src/Main.elm --output=main.js --optimize

if [ $? -eq 0 ]; then
    echo "✓ Build successful!"
    echo "Open index.html in your browser to play Tetris"
else
    echo "✗ Build failed"
    exit 1
fi
