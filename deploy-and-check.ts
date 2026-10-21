/**
 * 追加した機能を、デプロイして実際に呼んで確かめる。
 *
 *   npm run check:local     # Hardhat の内蔵ネットワーク(鍵も ETH も不要)
 *   npm run check:sepolia   # Sepolia。環境変数 SEPOLIA_RPC_URL と SEPOLIA_PRIVATE_KEY が必要
 *
 * チェック項目
 *   Store:          exists / 登録時の入力チェック(NotAContract, DuplicateVersion)
 *   ERC721Extended: itemIdOf / baseURIIndexOf / pinBaseURI の範囲チェック /
 *                   onERC721Received の中から itemIdOf が読めること / baseURIs() が配列を返すこと
 *
 * 1つでも期待と違えば、終了コード 1 で終わる。
 */
import { network } from "hardhat";
import { BaseError, ContractFunctionRevertedError, getAddress, type Hash } from "viem";
import { generatePrivateKey, privateKeyToAccount } from "viem/accounts";

const { viem, networkName } = await network.create();
const publicClient = await viem.getPublicClient();
const [owner] = await viem.getWalletClients();
const me = getAddress(owner.account.address); // コントラクトが返すアドレスと比べるため、チェックサム付きにそろえる

let failures = 0;

function check(label: string, actual: unknown, expected: unknown): void {
  const ok = JSON.stringify(actual, bigintReplacer) === JSON.stringify(expected, bigintReplacer);
  if (!ok) failures++;
  console.log(
    `  ${ok ? "OK" : "NG"}  ${label}: ${JSON.stringify(actual, bigintReplacer)}` +
      (ok ? "" : `  (期待値: ${JSON.stringify(expected, bigintReplacer)})`),
  );
}

function bigintReplacer(_key: string, value: unknown): unknown {
  return typeof value === "bigint" ? value.toString() : value;
}

/** トランザクションを送り、確定まで待つ。失敗したら例外にする */
async function send(label: string, tx: Promise<Hash>): Promise<void> {
  const hash = await tx;
  const receipt = await publicClient.waitForTransactionReceipt({ hash });
  if (receipt.status !== "success") throw new Error(`${label} が失敗した: ${hash}`);
  console.log(`  tx  ${label} (${hash})`);
}

/** 送らずに実行(eth_call)し、revert したエラーの名前を返す。revert しなければ "(revert しない)" */
async function revertName(call: Promise<unknown>): Promise<string> {
  try {
    await call;
    return "(revert しない)";
  } catch (err) {
    const reverted =
      err instanceof BaseError ? err.walk((e) => e instanceof ContractFunctionRevertedError) : null;
    if (reverted instanceof ContractFunctionRevertedError) {
      return reverted.data?.errorName ?? reverted.signature ?? "(不明なエラー)";
    }
    throw err;
  }
}

console.log(`network: ${networkName}`);
console.log(`account: ${me}`);

//  デプロ
console.log("\n=== デプロイ ===");
const nft = await viem.deployContract("ERC721Extended", ["Extended", "EXT"]);
const store = await viem.deployContract("Store");
const reader = await viem.deployContract("ItemReader");
console.log(`  ERC721Extended: ${nft.address}`);
console.log(`  Store:          ${store.address}`);
console.log(`  ItemReader:     ${reader.address}`);

// ---------------------------------------------------------------------
//  Store: exists と 登録時の入力チェック
// ---------------------------------------------------------------------
console.log("\n=== Store: exists ===");
check("登録前の exists(0)", await store.read.exists([0n]), false);

await send("registerSeries(nft, 10, 1)", store.write.registerSeries([nft.address, 10n, 1n, true, "ipfs://s10-v1"]));
check("登録後の exists(0)", await store.read.exists([0n]), true);
check("exists(1)(未登録)", await store.read.exists([1n]), false);

const s0 = await store.read.getSeriesById([0n]);
check("id0 の name(nft.name() から取得)", s0.name, "Extended");
check("id0 の creator(nft.owner() から取得)", s0.creator, me);

console.log("\n=== Store: 登録時の入力チェック ===");
const eoa = privateKeyToAccount(generatePrivateKey()).address; // コードのない、新しいアドレス
check(
  "EOA を登録",
  await revertName(store.simulate.registerSeries([eoa, 30n, 1n, true, "x"], { account: owner.account })),
  "NotAContract",
);
check(
  "同じ (seriesId 10, version 1) をもう一度登録",
  await revertName(store.simulate.registerSeries([nft.address, 10n, 1n, false, "dup"], { account: owner.account })),
  "DuplicateVersion",
);
check(
  "別の version (10, 2) は登録できる",
  await revertName(store.simulate.registerSeries([nft.address, 10n, 2n, false, "ok"], { account: owner.account })),
  "(revert しない)",
);
check(
  "別の seriesId (20, 1) は登録できる",
  await revertName(store.simulate.registerSeries([nft.address, 20n, 1n, false, "ok"], { account: owner.account })),
  "(revert しない)",
);


//  ERC721Extended: baseURI と pinBaseURI の範囲チェック

console.log("\n=== ERC721Extended: baseURIs と pinBaseURI ===");
await send('addBaseURI("ipfs://a/", false)', nft.write.addBaseURI(["ipfs://a/", false]));
await send('addBaseURI("ipfs://b/", true)', nft.write.addBaseURI(["ipfs://b/", true]));

const [pinnedIndex, uris, pinned] = await nft.read.baseURIs();
check("baseURIs() の pin している index", pinnedIndex, 1n);
check("baseURIs() の配列(登録済みの全件)", uris, ["ipfs://a/", "ipfs://b/"]);
check("baseURIs() の pinned", pinned, true);

check("pinBaseURI(0)(有効)", await revertName(nft.simulate.pinBaseURI([0n], { account: owner.account })), "(revert しない)");
check("pinBaseURI(1)(有効)", await revertName(nft.simulate.pinBaseURI([1n], { account: owner.account })), "(revert しない)");
check(
  "pinBaseURI(2)(index == length は範囲外)",
  await revertName(nft.simulate.pinBaseURI([2n], { account: owner.account })),
  "BaseURINotExists",
);

// ERC721Extended: itemIdOf / baseURIIndexOf

console.log("\n=== ERC721Extended: itemIdOf / baseURIIndexOf ===");
await send("setTotalItems(3)", nft.write.setTotalItems([3n]));
await send("setIsActive(true)", nft.write.setIsActive([true]));

const price = await nft.read.price();
await send("safePurchase(me, 2)  → token 0", nft.write.safePurchase([me, 2n], { value: price }));
await send("pinBaseURI(0)", nft.write.pinBaseURI([0n]));
await send("safePurchase(me, 3)  → token 1", nft.write.safePurchase([me, 3n], { value: price }));

check("itemIdOf(0)", await nft.read.itemIdOf([0n]), 2n);
check("baseURIIndexOf(0)(b を pin 中にミント)", await nft.read.baseURIIndexOf([0n]), 1n);
check("tokenURI(0)", await nft.read.tokenURI([0n]), "ipfs://b/2");
check("itemIdOf(1)", await nft.read.itemIdOf([1n]), 3n);
check("baseURIIndexOf(1)(a を pin し直してからミント)", await nft.read.baseURIIndexOf([1n]), 0n);
check("tokenURI(1)", await nft.read.tokenURI([1n]), "ipfs://a/3");
check("itemIdOf(999)(存在しないトークン)", await revertName(nft.read.itemIdOf([999n])), "ERC721NonexistentToken");

console.log("\n=== ERC721Extended: onERC721Received の中から itemIdOf を読む ===");
await send("safePurchase(reader, 2)  → token 2", nft.write.safePurchase([reader.address, 2n], { value: price }));
check("ItemReader が受け取り時に読んだ itemId", await reader.read.seenItemId(), 2n);

// ---------------------------------------------------------------------
console.log(`\n結果: ${failures === 0 ? "すべて期待どおり" : `${failures} 件が期待と違う`}`);
process.exitCode = failures === 0 ? 0 : 1;
