import {
    time,
    loadFixture,
} from "@nomicfoundation/hardhat-toolbox-viem/network-helpers";
import { expect } from "chai";
import hre from "hardhat";
import { getAddress, parseEther } from "viem";

// --- Print function ---
function getPrintCell(isRevealed: boolean, hasMine: boolean, mineCount: number) {
    let output = "";
    if (!isRevealed) output += "H ";
    else if (mineCount > 0) output += `${mineCount} `;
    else if (mineCount === 0) output += "0 ";

    return output;
}

function printBoard(board: number[]) {
    const size = Math.sqrt(board.length);
    let output = "Board:\n";
    for (let i = 0; i < size; i++) {
        for (let j = 0; j < size; j++) {
            const cell = board[i * size + j];
            const mineCount = (cell >> 2) & 0xF; // Extract bits 2-5
            output += `${mineCount} `;
        }
        output += "\n";
    }
    console.log(output);
}


// --- Helper Bit Manipulation Functions ---
function jsSetRevealed(cell: number): number {
    return cell | 1; // Set bit 0
}

function jsSetMine(cell: number): number {
    return cell | (1 << 1); // Set bit 1
}

function jsSetMineCount(cell: number, count: number): number {
    return (cell & 0xC3) | (count << 2); // Clear bits 2-5, set count
}

function jsIsRevealed(cell: number): boolean {
    return (cell & 1) !== 0;
}

function jsHasMine(cell: number): boolean {
    return (cell & (1 << 1)) !== 0;
}

function jsGetMineCount(cell: number): number {
    return (cell >> 2) & 0xF; // Extract bits 2-5
}

describe("Monadsweeper", function () {
    async function deployMonadsweeperFixture() {
        const REWARD = parseEther("1");
        const BOARD_SIZE = 9;
        const TOTAL_CELLS = BOARD_SIZE * BOARD_SIZE;
        const NUM_MINES = 10;

        // Deploy contract
        const [owner, player] = await hre.viem.getWalletClients();
        const Monadsweeper = await hre.viem.deployContract("Monadsweeper", []);
        const publicClient = await hre.viem.getPublicClient();
        // const walletClient = await hre.viem.getWalletClient("0x279e2071b5337F40C2932Aaef5E4F5B01A5A08F3");

        return {
            Monadsweeper,
            REWARD,
            BOARD_SIZE,
            TOTAL_CELLS,
            NUM_MINES,
            owner,
            player,
            publicClient
        };
    }

    describe("Deployment", function () {
        it("Should deploy with no initial games", async function () {
            const { Monadsweeper } = await loadFixture(deployMonadsweeperFixture);
            expect(await Monadsweeper.read.gameCount()).to.equal(0n);
        });
    });

    describe("Bit manipulation functions", function () {
        it("Should correctly extract mine count for various cell states", async function () {
            const { Monadsweeper } = await loadFixture(deployMonadsweeperFixture);

            // Test cases: cell value with different mine counts (0 to 8)
            const testCases = [
                { cell: 0b00000000, expected: 0 }, // mineCount = 0
                { cell: 0b00000100, expected: 1 }, // mineCount = 1 (0001 << 2)
                { cell: 0b00001000, expected: 2 }, // mineCount = 2 (0010 << 2)
                { cell: 0b00001100, expected: 3 }, // mineCount = 3 (0011 << 2)
                { cell: 0b00010000, expected: 4 }, // mineCount = 4 (0100 << 2)
                { cell: 0b00010100, expected: 5 }, // mineCount = 5 (0101 << 2)
                { cell: 0b00011000, expected: 6 }, // mineCount = 6 (0110 << 2)
                { cell: 0b00011100, expected: 7 }, // mineCount = 7 (0111 << 2)
                { cell: 0b00100000, expected: 8 }, // mineCount = 8 (1000 << 2)
            ];

            for (const { cell, expected } of testCases) {
                const result = await Monadsweeper.read.testGetMineCount([cell]);
                expect(result).to.equal(expected, `Failed for cell value ${cell.toString(2).padStart(8, '0')}`);
            }
        });

        it("Should ignore isRevealed and hasMine flags for correctly extract mine count", async function () {
            const { Monadsweeper } = await loadFixture(deployMonadsweeperFixture);

            // Test with mineCount = 8, varying isRevealed and hasMine
            const baseMineCount = 0b00100000; // mineCount = 8 (1000 << 2)
            const testCases = [
                { cell: baseMineCount | 0b00000001, expected: 8 }, // isRevealed = true
                { cell: baseMineCount | 0b00000010, expected: 8 }, // hasMine = true
                { cell: baseMineCount | 0b00000011, expected: 8 }, // Both true
                { cell: baseMineCount, expected: 8 }, // Neither true
            ];

            for (const { cell, expected } of testCases) {
                const result = await Monadsweeper.read.testGetMineCount([cell]);
                expect(result).to.equal(expected, `Failed for cell value ${cell.toString(2).padStart(8, '0')}`);
            }
        });

        // it("Should handle edge cases with invalid mine counts", async function () {
        //     const { Monadsweeper } = await loadFixture(deployMonadsweeperFixture);

        //     // Test with mineCount > 8 (4-bit values)
        //     const testCases = [
        //         { cell: 0b00100100, expected: 9 }, // mineCount = 9 (1001 << 2)
        //         { cell: 0b00111100, expected: 15 }, // mineCount = 15 (1111 << 2)
        //         { cell: 0b11111111, expected: 15 }, // All bits set, max mineCount = 15
        //     ];

        //     for (const { cell, expected } of testCases) {
        //         const result = await Monadsweeper.read.testGetMineCount([cell]);
        //         expect(result).to.equal(expected, `Failed for cell value ${cell.toString(2).padStart(8, '0')}`);
        //     }
        // });
    });

    describe("Game Initialization", function () {
        it("Should start a new game and emit GameStarted event", async function () {
            const { Monadsweeper, player } = await loadFixture(deployMonadsweeperFixture);

            // We retrieve the contract with a different account to send a transaction
            const startGameAsPlayer = await hre.viem.getContractAt(
                "Monadsweeper",
                Monadsweeper.address,
                { client: { wallet: player } }
            );
            // Start a new game
            await expect(startGameAsPlayer.write.startGame()).to.be.fulfilled;

            // Check that the game count has increased
            expect(await startGameAsPlayer.read.gameCount()).to.equal(1n);

            const game = await startGameAsPlayer.read.games([player.account.address]);
            expect(game[0]).to.be.true; // isActive
            expect(game[1]).to.equal(0); // revealedCount
            expect(game[2]).to.equal(getAddress(player.account.address)); // player
            expect(game[3]).to.be.false; // hasLost
            expect(game[4]).to.be.true; // firstMove

            // Check that the event was emitted with correct parameters
            const gameStartedEvent = await startGameAsPlayer.getEvents.GameStarted();
            expect(gameStartedEvent).to.have.lengthOf(1);
            expect((gameStartedEvent[0].args as { player: string }).player).to.equal(getAddress(player.account.address));
        });

        it("Should revert if the player is already in a game", async function () {
            const { Monadsweeper, player } = await loadFixture(deployMonadsweeperFixture);

            // We retrieve the contract with a different account to send a transaction
            const startGameAsPlayer = await hre.viem.getContractAt(
                "Monadsweeper",
                Monadsweeper.address,
                { client: { wallet: player } }
            );

            // Start a new game
            await startGameAsPlayer.write.startGame();

            // Attempt to start another game
            await expect(startGameAsPlayer.write.startGame()).to.be.rejectedWith("Already in a game");

        })
    })

    describe("Gameplay", function () {
        it("Should generate board on first dig with no mine or number at clicked cell", async function () {
            const { Monadsweeper, player } = await loadFixture(deployMonadsweeperFixture);
            const addrPlayer = getAddress(player.account.address);
            const checkX = 2;
            const checkY = 3;

            const startGameAsPlayer = await hre.viem.getContractAt(
                "Monadsweeper",
                Monadsweeper.address,
                { client: { wallet: player } }
            );

            await expect(startGameAsPlayer.write.startGame()).to.be.fulfilled; 
            await expect(startGameAsPlayer.write.dig([checkX, checkY])).to.be.fulfilled; // first move

            // Clear: stateCell is [cell:uint8, isRevealed: bool, hasMine: bool, mineCount: uint8]
            const stateCell = await startGameAsPlayer.read.getCell([addrPlayer, checkX, checkY]);

            expect(jsIsRevealed(stateCell[0])).to.be.true; // isRevealed
            expect(jsHasMine(stateCell[0])).to.be.false; // hasMine
            expect(jsGetMineCount(stateCell[0])).to.equal(0); // No adjacent mines due to no-guess mode

            // Verify adjacent cells have no mines
            for (let i = -1; i <= 1; i++) {
                for (let j = -1; j <= 1; j++) {
                    if (i === 0 && j === 0) continue;
                    const x = checkX + i;
                    const y = checkY + j;
                    if (x >= 0 && x < 9 && y >= 0 && y < 9) {
                        const adjCell = await Monadsweeper.read.getCell([addrPlayer, x, y]);
                        expect(jsHasMine(adjCell[0])).to.be.false;
                    }
                }
            }

            const cellRevealedEvents = await Monadsweeper.getEvents.CellRevealed();
            expect(cellRevealedEvents[0].args.player).to.equal(getAddress(player.account.address));
            expect(cellRevealedEvents[0].args.x).to.equal(checkX);
            expect(cellRevealedEvents[0].args.y).to.equal(checkY);
            expect(cellRevealedEvents[0].args.mineCount).to.equal(0);
        })

        // // How to check it? It is not possible to check the board state after the first move, because it is generated randomly.
        // it("Should win if all non-mine cells revealed", async function () {})


        it("Should lose if digging a mine", async function () {
            const { Monadsweeper, BOARD_SIZE, player } = await loadFixture(deployMonadsweeperFixture);
            const addrPlayer = getAddress(player.account.address);

            const startGameAsPlayer = await hre.viem.getContractAt(
                "Monadsweeper",
                Monadsweeper.address,
                { client: { wallet: player } }
            );
            const cellX = 0;
            const cellY = 0;


            await expect(startGameAsPlayer.write.startGame()).to.be.fulfilled;
            await expect(startGameAsPlayer.write.dig([cellX, cellY])).to.be.fulfilled;

            // Find a mine by checking all cells (simulating player finding a mine)
            let cellHasCountX = 0;
            let cellHasCountY = 0;
            let outputPrint = "Board:\n";

            for (let x = 0; x < BOARD_SIZE; x++) {
                for (let y = 0; y < BOARD_SIZE; y++) {
                    const cell = await startGameAsPlayer.read.getCell([addrPlayer, x, y]);
                    outputPrint += getPrintCell(jsIsRevealed(cell[0]), jsHasMine(cell[0]), jsGetMineCount(cell[0]));
                    if (jsIsRevealed(cell[0]) && jsGetMineCount(cell[0]) > 0) {
                        // Check the adjacent cells for a mine
                        cellHasCountX = x;
                        cellHasCountY = y;
                        // break;
                    }
                }
                outputPrint += "\n";
            }
            // console.log(outputPrint);

            let gameLose = false;
            for (let i = -1; i <= 1 && !gameLose; i++) {
                for (let j = -1; j <= 1 && !gameLose; j++) {
                    if (i === 0 && j === 0) continue;
                    const adjX = cellHasCountX + i;
                    const adjY = cellHasCountY + j;
                    if (adjX >= 0 && adjX < BOARD_SIZE && adjY >= 0 && adjY < BOARD_SIZE) {
                        let adjCell = await startGameAsPlayer.read.getCell([addrPlayer, adjX, adjY]);
                        if (!jsIsRevealed(adjCell[0])) {
                            // dig
                            await expect(startGameAsPlayer.write.dig([adjX, adjY])).to.be.fulfilled;

                            // check status of game
                            const game = await Monadsweeper.read.games([addrPlayer]);
                            const isActive = game[0];
                            const hasLost = game[3];

                            // check the cell has just been revealed
                            if (!isActive && hasLost) {
                                const gameLostEvents = await Monadsweeper.getEvents.GameLost();
                                expect(gameLostEvents).to.have.lengthOf(1);
                                expect(gameLostEvents[0].args.player).to.equal(addrPlayer);
                                expect(gameLostEvents[0].args.x).to.equal(adjX);
                                expect(gameLostEvents[0].args.y).to.equal(adjY);
                                gameLose = true;
                            }
                            else {
                                // update the cell state and check state
                                adjCell = await startGameAsPlayer.read.getCell([addrPlayer, adjX, adjY]);
                                expect(jsIsRevealed(adjCell[0])).to.be.true; // isRevealed
                                expect(jsHasMine(adjCell[0])).to.be.false; // hasMine
                            }
                        }
                    }
                }
            }
        });

        it("Should revert if digging already revealed cell", async function () {
            const { Monadsweeper } = await loadFixture(deployMonadsweeperFixture);

            await expect(Monadsweeper.write.startGame()).to.be.fulfilled;
            await expect(Monadsweeper.write.dig([0, 0])).to.be.fulfilled; // first move

            await expect(Monadsweeper.write.dig([0, 0])).to.be.rejectedWith("Cell already revealed"); // second move
        });

        it("Should revert if digging with invalid coordinates", async function () {
            const { Monadsweeper } = await loadFixture(deployMonadsweeperFixture);

            await expect(Monadsweeper.write.startGame()).to.be.fulfilled;
            await expect(Monadsweeper.write.dig([9, 0])).to.be.rejectedWith("Invalid coordinates");
            await expect(Monadsweeper.write.dig([0, 9])).to.be.rejectedWith("Invalid coordinates");
        });

        it("Should revert if digging with no active game", async function () {
            const { Monadsweeper } = await loadFixture(deployMonadsweeperFixture);
            await expect(Monadsweeper.write.dig([0, 0])).to.be.rejectedWith("No active game");
        });
    })

    describe("Cell State", function () {
        it("Shouldn't return cell state for unrevealed cell", async function () {
            const { Monadsweeper, owner } = await loadFixture(deployMonadsweeperFixture);
            const addrPlayer = getAddress(owner.account.address);

            await expect(Monadsweeper.write.startGame()).to.be.fulfilled;
            const cell = await Monadsweeper.read.getCell([addrPlayer, 0, 0]);
            expect(jsIsRevealed(cell[0])).to.be.false;
            expect(jsHasMine(cell[0])).to.be.false;
            expect(jsGetMineCount(cell[0])).to.equal(0);
        });

        it("Should return correct cell state for revealed cell", async function () {
            const { Monadsweeper, owner } = await loadFixture(deployMonadsweeperFixture);
            const addrPlayer = getAddress(owner.account.address);

            await expect(Monadsweeper.write.startGame()).to.be.fulfilled;
            await expect(Monadsweeper.write.dig([0, 0])).to.be.fulfilled;
            const cell = await Monadsweeper.read.getCell([addrPlayer, 0, 0]);
            expect(jsIsRevealed(cell[0])).to.be.true;
            expect(jsHasMine(cell[0])).to.be.false;
            expect(jsGetMineCount(cell[0])).to.equal(0);
        });
    });
})
