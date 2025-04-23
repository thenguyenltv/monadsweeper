import {
    time,
    loadFixture,
} from "@nomicfoundation/hardhat-toolbox-viem/network-helpers";
import { expect } from "chai";
import hre from "hardhat";
import { getAddress, parseEther } from "viem";

describe("Minesweeper", function () {
    async function deployMinesweeperFixture() {
        const REWARD = parseEther("0.01");
        const BOARD_SIZE = 9;
        const TOTAL_CELLS = BOARD_SIZE * BOARD_SIZE;
        const NUM_MINES = 10;

        // Deploy contract
        const [owner, player] = await hre.viem.getWalletClients();
        const minesweeper = await hre.viem.deployContract("Minesweeper", []);
        const publicClient = await hre.viem.getPublicClient();
        // const walletClient = await hre.viem.getWalletClient();

        return { minesweeper, REWARD, BOARD_SIZE, TOTAL_CELLS, NUM_MINES, owner, player, publicClient };
    }

    describe("Deployment", function () {
        it("Should deploy with no initial games", async function () {
            const { minesweeper } = await loadFixture(deployMinesweeperFixture);
            expect(await minesweeper.read.gameCount()).to.equal(0n);
        });
    });

    describe("getMineCount", function () {
        it("Should correctly extract mine count for various cell states", async function () {
            const { minesweeper } = await loadFixture(deployMinesweeperFixture);

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
                const result = await minesweeper.read.testGetMineCount([cell]);
                expect(result).to.equal(expected, `Failed for cell value ${cell.toString(2).padStart(8, '0')}`);
            }
        });

        it("Should ignore isRevealed and hasMine flags", async function () {
            const { minesweeper } = await loadFixture(deployMinesweeperFixture);

            // Test with mineCount = 8, varying isRevealed and hasMine
            const baseMineCount = 0b00100000; // mineCount = 8 (1000 << 2)
            const testCases = [
                { cell: baseMineCount | 0b00000001, expected: 8 }, // isRevealed = true
                { cell: baseMineCount | 0b00000010, expected: 8 }, // hasMine = true
                { cell: baseMineCount | 0b00000011, expected: 8 }, // Both true
                { cell: baseMineCount, expected: 8 }, // Neither true
            ];

            for (const { cell, expected } of testCases) {
                const result = await minesweeper.read.testGetMineCount([cell]);
                expect(result).to.equal(expected, `Failed for cell value ${cell.toString(2).padStart(8, '0')}`);
            }
        });

        it("Should handle edge cases with invalid mine counts", async function () {
            const { minesweeper } = await loadFixture(deployMinesweeperFixture);

            // Test with mineCount > 8 (4-bit values)
            const testCases = [
                { cell: 0b00100100, expected: 9 }, // mineCount = 9 (1001 << 2)
                { cell: 0b00111100, expected: 15 }, // mineCount = 15 (1111 << 2)
                { cell: 0b11111111, expected: 15 }, // All bits set, max mineCount = 15
            ];

            for (const { cell, expected } of testCases) {
                const result = await minesweeper.read.testGetMineCount([cell]);
                expect(result).to.equal(expected, `Failed for cell value ${cell.toString(2).padStart(8, '0')}`);
            }
        });
    });
})
