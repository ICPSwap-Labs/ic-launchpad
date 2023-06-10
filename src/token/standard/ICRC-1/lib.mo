import Array         "mo:base/Array";
import Blob          "mo:base/Blob";
import Buffer        "mo:base/Buffer";
import Principal     "mo:base/Principal";
import Option        "mo:base/Option";
import Error         "mo:base/Error";
import Time          "mo:base/Time";
import Int           "mo:base/Int";
import Nat8          "mo:base/Nat8";
import Nat64         "mo:base/Nat64";
import Types "../../TokenTypes";
import HashMap "mo:base/HashMap";
import Text "mo:base/Text";
import Nat "mo:base/Nat";

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

    public class ICRC1TokenAdapter(cid: Text): Types.TokenAdapter = this {
        let canister = actor(cid): actor { 
            icrc1_transfer: shared (TransferArgs) -> async TransferResult;
            icrc1_balance_of: query (Account) -> async Amount;
            icrc1_total_supply: query () -> async Amount;
            icrc1_symbol: query () -> async Text;
            icrc1_decimals: query () -> async Nat8;
            icrc1_fee: query () -> async Nat;
            icrc1_metadata: query () -> async [(Text, Value)];
        };
        public func valid(): async Bool { 
            try {
                let symbol: Text = await canister.icrc1_symbol();
                return true;
            } catch(e) {
                return false;
            };
        };
        public func balanceOf(account : Account): async Amount { 
            return await canister.icrc1_balance_of(account);
        };
        public func totalSupply(): async Amount { 
            return await canister.icrc1_total_supply();
         };
        public func symbol(): async Text { 
            return await canister.icrc1_symbol();
        };
        public func decimals(): async Nat8 { 
            return await canister.icrc1_decimals();
        };
        public func fee(): async Nat { 
            return await canister.icrc1_fee();
        };
        public func metadata(): async [(Text, Value)] { 
            let metadata: [(Text, Value)] = await canister.icrc1_metadata();
            let metadata_map: HashMap.HashMap<Text, Value> = HashMap.fromIter<Text, Value>(metadata.vals(), 4, Text.equal, Text.hash);
            let name: Value = Option.get(metadata_map.get("icrc1:name"), #Text(""));
            let symbol: Value = Option.get(metadata_map.get("icrc1:symbol"), #Text(""));
            let decimals: Value = Option.get(metadata_map.get("icrc1:decimals"), #Nat(0));
            let fee: Value = Option.get(metadata_map.get("icrc1:fee"), #Nat(0));
            [
                ("name", name),
                ("symbol", symbol),
                ("decimals", decimals),
                ("fee", fee),
            ]
        };  
        public func transfer(args: TransferArgs): async TransferResult {
            return await canister.icrc1_transfer(args);
        };
        public func approve(args: ApproveArgs): async ApproveResult { 
            throw Error.reject("Unsupport method 'approve'.");
        };
        public func transferFrom(args: TransferFromArgs): async TransferFromResult {
            throw Error.reject("Unsupport method 'transferFrom'."); 
        };
    }
}