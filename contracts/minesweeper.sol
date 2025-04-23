// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

// Uncomment this line to use console.log
import "hardhat/console.sol";

contract Minesweeper {
    address public owner;

    constructor() {
        owner = msg.sender;
    }

    // Fixed 9x9 board (81 cells) with 10 mines
    // Fixed 12*12 board (81 cells) with 28 mines (numMine = h * w / 5)
    uint16 constant BOARD_SIZE = 9;
    uint16 constant TOTAL_CELLS = BOARD_SIZE * BOARD_SIZE;
    uint16 constant NUM_MINES = 10;
    uint256 constant REWARD = 0.01 ether;

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
        require(msg.value == REWARD, "Must send exact reward");
        require(!games[msg.sender].isActive, "Game already active");

        Game storage game = games[msg.sender];
        game.isActive = true;
        game.player = msg.sender;
        game.revealedCount = 0;
        game.hasLost = false;
        game.firstMove = true;

        // Clear board using assembly for gas savings
        assembly {
            let board := sload(add(game.slot, 1)) // Point to board array
            for {
                let i := 0
            } lt(i, 81) {
                i := add(i, 1)
            } {
                mstore(add(board, mul(i, 32)), 0)
            }
        }

        gameCount++;
        emit GameStarted(msg.sender, gameCount);
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
            uint16 index = uint16(seed % TOTAL_CELLS);
            seed = uint256(keccak256(abi.encodePacked(seed)));

            // Convert index to coordinates for adjacency check
            uint16 x = index / BOARD_SIZE;
            uint16 y = index % BOARD_SIZE;

            // Skip if mine is at first click or adjacent
            if (
                index == firstIndex ||
                (x >= firstX - 1 &&
                    x <= firstX + 1 &&
                    y >= firstY - 1 &&
                    y <= firstY + 1 &&
                    x < BOARD_SIZE &&
                    y < BOARD_SIZE) ||
                hasMine(game.board[index])
            ) {
                continue;
            }

            game.board[index] = setMine(game.board[index]);
            minesPlaced++;
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
    }

    // Dig (reveal) a cell
    function dig(
        uint16 x,
        uint16 y
    ) public onlyActiveGame validCoordinates(x, y) {
        Game storage game = games[msg.sender];
        uint8 cell = game.board[toIndex(x, y)];

        require(!isRevealed(cell), "Cell already revealed");

        if (game.firstMove) {
            generateMines(game, x, y);
            game.firstMove = false;
        }

        uint16[][2] memory stack = [
            new uint16[](BOARD_SIZE * BOARD_SIZE),
            new uint16[](BOARD_SIZE * BOARD_SIZE)
        ];
        uint256 stackSize = 0;

        // Push ô đầu tiên vào stack
        stack[0][stackSize] = x;
        stack[1][stackSize] = y;
        stackSize++;

        while (stackSize > 0) {
            // Pop từ stack
            stackSize--;
            uint16 currX = stack[0][stackSize];
            uint16 currY = stack[1][stackSize];

            uint16 currIndex = toIndex(currX, currY);
            uint8 currCell = game.board[currIndex];

            if (isRevealed(currCell)) continue; // Pass the duplicate cell push to stack

            game.board[currIndex] = setRevealed(currCell);

            if (hasMine(currCell)) {
                game.isActive = false;
                game.hasLost = true;
                emit GameLost(msg.sender, x, y);
                return;
            }

            if (getMineCount(currCell) > 0) {
                game.revealedCount++;
                emit CellRevealed(
                    msg.sender,
                    currX,
                    currY,
                    getMineCount(currCell)
                );
                continue;
            }

            // getMineCount(currCell)==0, reveal adjacent cells (cân nhắc)
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
                        uint8 neighbor = game.board[
                            toIndex(uint16(newX), uint16(newY))
                        ];
                        if (isRevealed(neighbor)) continue; // Skip if already revealed
                        stack[0][stackSize] = uint16(newX);
                        stack[1][stackSize] = uint16(newY);
                        stackSize++;
                    }
                }
            }

            if (_isWinner(msg.sender)) {
                game.isActive = false;
                payable(msg.sender).transfer(REWARD);
                emit GameWon(msg.sender, REWARD);
            }
        }
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
}
