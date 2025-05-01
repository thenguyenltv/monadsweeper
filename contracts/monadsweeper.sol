// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

// Uncomment this line to use console.log
// import "hardhat/console.sol";

contract Monadsweeper {
    address public owner;

    constructor() {
        owner = msg.sender;
    }

    // Fixed 9x9 board (81 cells) with 10 mines
    // Fixed 12*12 board (81 cells) with 28 mines (numMine = h * w / 5)
    uint16 constant BOARD_SIZE = 9;
    uint16 constant TOTAL_CELLS = BOARD_SIZE * BOARD_SIZE;
    uint16 constant NUM_MINES = 10;
    uint256 constant REWARD = 1 ether;

    // Cell state in a single uint16 using bit fields:
    // Bit 0: isRevealed (1 = revealed, 0 = hidden)
    // Bit 1: hasMine (1 = mine, 0 = no mine)
    // Bits 2-5: mineCount (0-8 adjacent mines, 4 bits)
    // Bits 6-7: Unused
    struct Game {
        uint8[TOTAL_CELLS] board; // 1D array for gas efficiency
        bool isActive;
        uint16 revealedCount;
        address player;
        bool hasLost;
        bool firstMove;
    }

    mapping(address => Game) public games;
    uint256 public gameCount;

    event GameStarted(address indexed player, uint256 gameId);
    event CellRevealed(
        address indexed player,
        uint16 x,
        uint16 y,
        uint16 mineCount
    );
    event GameWon(address indexed player, uint256 reward);
    event GameLost(address indexed player, uint16 x, uint16 y);

    modifier onlyActiveGame() {
        require(games[msg.sender].isActive, "No active game");
        _;
    }

    modifier validCoordinates(uint16 x, uint16 y) {
        require(x < BOARD_SIZE && y < BOARD_SIZE, "Invalid coordinates");
        _;
    }

    // Start a new game
    function startGame() external payable {
        // require(msg.value == REWARD, "Must send exact reward");
        require(!games[msg.sender].isActive, "Already in a game");

        Game storage game = games[msg.sender];

        // Clear board using assembly for gas savings
        for (uint256 i = 0; i < TOTAL_CELLS; i++) {
            game.board[i] = 0;
        }

        game.isActive = true;
        game.player = msg.sender;
        game.revealedCount = 0;
        game.hasLost = false;
        game.firstMove = true;

        gameCount++;
        emit GameStarted(msg.sender, gameCount);
    }

    function endGame() external onlyActiveGame {
        Game storage game = games[msg.sender];
        game.isActive = false;
        game.hasLost = true;
    }

    // Generate mines after first click
    function generateMines(
        Game storage game,
        uint16 firstX,
        uint16 firstY
    ) private {
        uint16 minesPlaced = 0;
        uint256 seed = uint256(
            keccak256(abi.encodePacked(block.timestamp, msg.sender, gameCount))
        ); // Sinh seed giả ngẫu nhiên tạm thời, sau này sẽ thay bằng oracle (VRF)
        uint16 firstIndex = toIndex(firstX, firstY);

        while (minesPlaced < NUM_MINES) {
            // console.log("Seed: %d", seed);
            uint16 index = uint16(seed % TOTAL_CELLS);
            seed = uint256(keccak256(abi.encodePacked(seed)));

            // Convert index to coordinates for adjacency check
            uint16 x = index / BOARD_SIZE;
            uint16 y = index % BOARD_SIZE;
            // console.log("[X, Y] at (%d, %d)", x, y);

            // Skip if mine is at first click or adjacent
            if (
                index == firstIndex ||
                (_isAjacent(x, y, firstX, firstY)) ||
                hasMine(game.board[index])
            ) {
                continue;
            }

            game.board[index] = setMine(game.board[index]);
            minesPlaced++;
            // console.log("Placed mine at (%d, %d)", x, y);
        }

        // Calculate mine counts
        for (uint16 i = 0; i < TOTAL_CELLS; i++) {
            if (!hasMine(game.board[i])) {
                uint16 x = i / BOARD_SIZE;
                uint16 y = i % BOARD_SIZE;
                game.board[i] = setMineCount(
                    game.board[i],
                    countAdjacentMines(game, x, y)
                );
            }
        }

        revealCells(game, firstX, firstY);
    }

    // Dig (reveal) a cell
    function dig(
        uint16 x,
        uint16 y
    ) public onlyActiveGame validCoordinates(x, y) {
        Game storage game = games[msg.sender];
        uint16 currIndex = toIndex(x, y);
        uint8 cell = game.board[currIndex];

        require(!isRevealed(cell), "Cell already revealed");

        if (game.firstMove) {
            generateMines(game, x, y);
            game.firstMove = false;
            return;
        }

        revealCells(game, x, y);

        if (_isWinner(msg.sender)) {
            game.isActive = false;
            // payable(msg.sender).transfer(REWARD);
            emit GameWon(msg.sender, REWARD);
        }
    }

    function revealCells(Game storage game, uint16 x, uint16 y) private {
        uint16[][2] memory stack = [
            new uint16[](BOARD_SIZE * BOARD_SIZE),
            new uint16[](BOARD_SIZE * BOARD_SIZE)
        ];
        uint256 stackSize = 0;

        stack[0][stackSize] = x;
        stack[1][stackSize] = y;
        stackSize++;

        while (stackSize > 0) {
            stackSize--;
            uint16 currX = stack[0][stackSize];
            uint16 currY = stack[1][stackSize];

            uint16 currIndex = toIndex(currX, currY);
            uint8 currCell = game.board[currIndex];

            if (isRevealed(currCell)) continue;

            game.board[currIndex] = setRevealed(currCell);
            currCell = game.board[currIndex];

            if (hasMine(currCell)) {
                game.isActive = false;
                game.hasLost = true;
                emit GameLost(msg.sender, currX, currY);
                return;
            }

            game.revealedCount++;
            emit CellRevealed(msg.sender, currX, currY, getMineCount(currCell));

            if (getMineCount(currCell) > 0) continue;

            stackSize = pushAdjacentCells(stack, stackSize, currX, currY, game);
        }
    }

    function pushAdjacentCells(
        uint16[][2] memory stack,
        uint256 stackSize,
        uint16 x,
        uint16 y,
        Game storage game
    ) private view returns (uint256) {

        for (int8 i = -1; i <= 1; i++) {
            for (int8 j = -1; j <= 1; j++) {
                if (i == 0 && j == 0) continue;
                stackSize = processAdjacentCell(stack, stackSize, x, y, i, j, game);
            }
        }
        return stackSize;
    }

    function processAdjacentCell(
        uint16[][2] memory stack,
        uint256 stackSize,
        uint16 x,
        uint16 y,
        int8 offsetX,
        int8 offsetY,
        Game storage game
    ) private view returns (uint256) {
        int16 newX = int16(x) + offsetX;
        int16 newY = int16(y) + offsetY;
        if (
            newX >= 0 &&
            newX < int16(BOARD_SIZE) &&
            newY >= 0 &&
            newY < int16(BOARD_SIZE)
        ) {
            uint8 neighbor = game.board[toIndex(uint16(newX), uint16(newY))];
            if (isRevealed(neighbor)) return stackSize; 
            stack[0][stackSize] = uint16(newX);
            stack[1][stackSize] = uint16(newY);
            return stackSize + 1;
        }
        return stackSize;
    }

    // --- Helper functions ---

    // Convert 2D coordinates to 1D index
    function toIndex(uint16 x, uint16 y) private pure returns (uint16) {
        return uint16(x * BOARD_SIZE + y);
    }

    // Count adjacent mines
    function countAdjacentMines(
        Game storage game,
        uint16 x,
        uint16 y
    ) private view returns (uint8) {
        uint8 count = 0;
        for (int8 i = -1; i <= 1; i++) {
            for (int8 j = -1; j <= 1; j++) {
                if (i == 0 && j == 0) continue;
                int16 newX = int16(x) + i;
                int16 newY = int16(y) + j;
                if (
                    newX >= 0 &&
                    newX < int16(BOARD_SIZE) &&
                    newY >= 0 &&
                    newY < int16(BOARD_SIZE)
                ) {
                    if (
                        hasMine(game.board[toIndex(uint16(newX), uint16(newY))])
                    ) {
                        count++;
                    }
                }
            }
        }
        return count;
    }

    function _isWinner(address player) internal view returns (bool) {
        Game storage game = games[player];
        return
            game.isActive &&
            !game.hasLost &&
            game.revealedCount == (TOTAL_CELLS - NUM_MINES);
    }

    function isWinner() public view returns (bool) {
        return _isWinner(msg.sender);
    }

    function _isAjacent(
        uint16 x,
        uint16 y,
        uint16 x0,
        uint16 y0
    ) private pure returns (bool) {
        // x, y is the cell to check
        // will check if (x, y) is adjacent to (x0, y0)
        // that means (x, y) is in the range of (x0-1, x0+1) and (y0-1, y0+1)
        // Also, check x0, y0 is in the range of (0, BOARD_SIZE-1)
        // because x, y, x0, y0 is type of uint16, so it can't be negative

        if (x0 >= BOARD_SIZE || y0 >= BOARD_SIZE) {
            return false; // x0, y0 out of bounds
        }

        // Handle x0 - 1 safely
        uint16 xMin = x0 == 0 ? 0 : x0 - 1;
        uint16 xMax = x0 + 1 >= BOARD_SIZE ? BOARD_SIZE - 1 : x0 + 1;

        uint16 yMin = y0 == 0 ? 0 : y0 - 1;
        uint16 yMax = y0 + 1 >= BOARD_SIZE ? BOARD_SIZE - 1 : y0 + 1;

        return (x >= xMin && x <= xMax && y >= yMin && y <= yMax);
    }

    // --- Bit manipulation functions ---

    function setRevealed(uint8 cell) private pure returns (uint8) {
        return cell | 1; // Set bit 0
    }

    function setMine(uint8 cell) private pure returns (uint8) {
        return cell | (1 << 1); // Set bit 1
    }

    function setMineCount(
        uint8 cell,
        uint8 count
    ) private pure returns (uint8) {
        return (cell & 0xC3) | (count << 2); // Clear bits 2-5, set count
        // 0xC3 = 11000011 in binary (clears bits 2-5)
    }

    function isRevealed(uint8 cell) private pure returns (bool) {
        return (cell & 1) != 0;
    }

    function hasMine(uint8 cell) private pure returns (bool) {
        return (cell & (1 << 1)) != 0;
    }

    function getMineCount(uint8 cell) private pure returns (uint8) {
        return (cell >> 2) & 0xF; // Extract bits 2-5
        // 0xF = 1111 in binary (extracts 4 bits)
    }

    // Public wrapper for testing getMineCount
    function testGetMineCount(uint8 cell) public pure returns (uint8) {
        return getMineCount(cell);
    }

    // Public wrapper for testing hasMine
    function testHasMine(uint8 cell) public pure returns (bool) {
        return hasMine(cell);
    }

    // --- Get functions ---
    function readValueCellFromUnit8(
        uint8 cell
    ) public pure returns (bool, bool, uint8) {
        return (isRevealed(cell), hasMine(cell), getMineCount(cell));
    }

    function getCell(
        address player,
        uint16 x,
        uint16 y
    ) public view validCoordinates(x, y) returns (uint8, bool, bool, uint8) {
        require(games[player].isActive, "No active game");

        uint8 cell = games[player].board[toIndex(x, y)];

        // require(isRevealed(cell), "Cell is not revealed");
        if (isRevealed(cell)) {
            return (cell, true, hasMine(cell), getMineCount(cell));
        }
        return (cell, false, hasMine(cell), getMineCount(cell));
    }
}
