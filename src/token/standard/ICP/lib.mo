import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Buffer "mo:base/Buffer";
import Principal "mo:base/Principal";
import Option "mo:base/Option";
import Error "mo:base/Error";
import Time "mo:base/Time";
import Int "mo:base/Int";
import Nat8 "mo:base/Nat8";
import Nat32 "mo:base/Nat32";
import Nat64 "mo:base/Nat64";
import Text "mo:base/Text";
import Prim "mo:⛔";
import SHA224 "mo:sha224/SHA224";
import CRC32 "./utils/CRC32";
import Types "../../TokenTypes";

module {
    public type Account = Types.Account;
    public type Subaccount = Types.Subaccount;
    public type Amount = Types.Amount;
    public type Memo = Types.Memo;
    public type Timestamp = Types.Timestamp;
    public type Duration = Types.Duration;
    public type TxIndex = Types.TxIndex;
    public type Value = { #Nat : Nat; #Int : Int; #Blob : Blob; #Text : Text; };
    public type TransferArgs = Types.TransferArgs;
    public type TransferFromArgs = Types.TransferFromArgs;
    public type TransferError = Types.TransferError;
    public type TransferResult = Types.TransferResult;
    public type ApproveArgs = Types.ApproveArgs;
    public type ApproveResult = Types.ApproveResult;
    public type TransferFromResult = Types.TransferFromResult;

    type Result<T, E> = {
        #Ok  : T;
        #Err : E;
    };
    type AccountIdentifier = Blob;
    type SubAccount = Blob;
    type AccountBalanceArgs = { 
        account : AccountIdentifier;
    };
    type Tokens = { e8s : Nat64 };
    type BlockHeight = Nat64;
    type ICPTransferArgs = {
        to : AccountIdentifier;
        fee : Tokens;
        memo : Nat64;
        from_subaccount : ?SubAccount;
        created_at_time : ?{ timestamp_nanos : Nat64 };
        amount : Tokens;
    };
    type ICPTransferError = {
        #BadFee : { expected_fee : Tokens };
        #InsufficientFunds : { balance: Tokens };
        #TxTooOld : { allowed_window_nanos: Nat64 };
        #TxCreatedInFuture;
        #TxDuplicate : { duplicate_of: BlockHeight; };
    };
    type ICPTransferResult = Result<BlockHeight, ICPTransferError>;

    func beBytes(n: Nat32) : [Nat8] {
        func byte(n: Nat32) : Nat8 {
            Nat8.fromNat(Nat32.toNat(n & 0xff))
        };
        [byte(n >> 24), byte(n >> 16), byte(n >> 8), byte(n)]
    };

    func defaultSubaccount() : SubAccount {
        Blob.fromArrayMut(Array.init(32, 0 : Nat8))
    };

    func accountIdentifier(principal: Principal, subaccount: SubAccount) : AccountIdentifier {
        let hash = SHA224.Digest();
        hash.write([0x0A]);
        hash.write(Blob.toArray(Text.encodeUtf8("account-id")));
        hash.write(Blob.toArray(Principal.toBlob(principal)));
        hash.write(Blob.toArray(subaccount));
        let hashSum : [Nat8] = hash.sum();
        let crc32Bytes : [Nat8] = beBytes(CRC32.ofArray(hashSum));
        var hashBuffer : Buffer.Buffer<Nat8> = Buffer.Buffer<Nat8>(crc32Bytes.size() + hashSum.size());
        for (value in crc32Bytes.vals()) {
        hashBuffer.add(value);
        };
        for (value in hashSum.vals()) {
        hashBuffer.add(value);
        };
        Blob.fromArray(hashBuffer.toArray())
    };

    public class ICPTokenAdapter(): Types.TokenAdapter = this {
        let LEDGER_CANISTER_ID : Text = "ryjl3-tyaaa-aaaaa-aaaba-cai";
        let WRAPPED_ICP_FEE : Nat = 10_000;

        let canister = actor(LEDGER_CANISTER_ID): actor {
            name : query () -> async { name: Text };
            symbol : query () -> async { symbol: Text };
            decimals : query () -> async { decimals: Nat32 };
            account_balance : shared query AccountBalanceArgs -> async Tokens;
            transfer : shared ICPTransferArgs -> async ICPTransferResult;
        };
        public func valid(): async Bool { 
            true
        };
        public func balanceOf(account : Account): async Amount {
            let subaccount: SubAccount = switch(account.subaccount) {
                case (?subaccount) { subaccount };
                case (null) { defaultSubaccount() };
            };
            let accountBalanceArgs: AccountBalanceArgs = {
                account = accountIdentifier(account.owner, subaccount);
            };
            let balance: Tokens = await canister.account_balance(accountBalanceArgs);
            Nat64.toNat(balance.e8s)
        };
        public func totalSupply(): async Amount { 
            return 49200000000000000000000;
         };
        public func symbol(): async Text { 
            return "ICP";
        };
        public func decimals(): async Nat8 { 
            return 8;
        };
        public func fee(): async Nat { 
            return WRAPPED_ICP_FEE;
        };
        public func metadata(): async [(Text, Value)] { 
            return [
                ("name", #Text("Internet Computer")),
                ("symbol", #Text("ICP")),
                ("decimals", #Nat(Nat8.toNat(8))),
                ("ownerAccount", #Text("")),
            ];
        };  
        public func transfer(args: TransferArgs): async TransferResult {
            let to_subaccount: SubAccount = switch(args.to.subaccount) {
                case (?subaccount) { subaccount };
                case (null) { defaultSubaccount() };
            };
            let res : ICPTransferResult = await canister.transfer({
                memo = 1;
                to = accountIdentifier(args.to.owner, to_subaccount);
                amount = {
                    e8s = Nat64.fromNat(args.amount);
                };
                fee = {
                    e8s = Nat64.fromNat(WRAPPED_ICP_FEE);
                };
                from_subaccount = args.from_subaccount;
                created_at_time = null;
            });
            switch (res) {
                case (#Ok(blockIndex)) {
                    return #Ok(Nat64.toNat(blockIndex));
                };
                case (#Err(#BadFee {expected_fee})) {
                    return #Err(#BadFee({ expected_fee = Nat64.toNat(expected_fee.e8s) }));
                };
                case (#Err(#InsufficientFunds {balance})) {
                    return #Err(#InsufficientFunds({ balance = Nat64.toNat(balance.e8s) }));
                };
                case (#Err(#TxTooOld(allowed_window_nanos))) {
                    return #Err(#TooOld);
                };
                case (#Err(#TxCreatedInFuture)) {
                    return #Err(#CreatedInFuture({ ledger_time = Prim.time() }));
                };
                case (#Err(#TxDuplicate {duplicate_of})) {
                    return #Err(#Duplicate({ duplicate_of = Nat64.toNat(duplicate_of) }));
                };
            };
        };
        public func approve(args: ApproveArgs): async ApproveResult { 
            throw Error.reject("Unsupport method 'approve'.");
        };
        public func transferFrom(args: TransferFromArgs): async TransferFromResult {
            throw Error.reject("Unsupport method 'transferFrom'."); 
        };
    }
}