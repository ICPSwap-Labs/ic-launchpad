import Text "mo:base/Text";
import Blob "mo:base/Blob";
import Nat8 "mo:base/Nat8";
import Principal "mo:base/Principal";
import Error "mo:base/Error";
import PrincipalUtils "mo:commons/PrincipalUtils";
import Types "../../TokenTypes";
import Debug "mo:base/Debug";
import Option "mo:base/Option";

module {
    public type DIP20TxReceipt = {
        #Ok: Nat;
        #Err: {
            #Unauthorized : Text;
            #InsufficientBalance;
            #InvalidToken : Text;
            #InsufficientAllowance;
            #CannotNotify : Text;
            #Other : Text;
            #Rejected;
            #ErrorOperationStyle;
            #LedgerTrap;
            #ErrorTo;
            #BlockUsed;
            #AmountTooSmall;
        };
    };
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
    
    
    public class DIP20TokenAdapter(cid: Text): Types.TokenAdapter = this {
        let canister = actor(cid): actor { 
            transferFrom: shared (from: Principal, to: Principal, value: Nat) -> async DIP20TxReceipt;
            transfer: shared (to: Principal, value: Nat) -> async DIP20TxReceipt;
            approve: shared (spender: Principal, value: Nat) -> async DIP20TxReceipt;
            balanceOf: query (who: Principal) -> async Nat;
            totalSupply: query () -> async Nat;
            symbol: query () -> async Text;
            decimals: query () -> async Nat8;
            getTokenFee: query () -> async Nat;
            getMetadata: query () -> async {
                logo : Text;
                name : Text;
                symbol : Text;
                decimals : Nat8;
                totalSupply : Nat;
                owner : Principal;
                fee : Nat;
            };
        };
        public func valid(): async Bool { 
            try {
                let metadata = await canister.getMetadata();
                return true;
            } catch(e) {
                return false;
            };
        };
        public func balanceOf(account : Account): async Amount {
            if (Option.isSome(account.subaccount)) {
                throw Error.reject("balanceOf: unspported_args_subaccount");
            };
            await canister.balanceOf(account.owner)
        };
        public func totalSupply(): async Amount { 
            await canister.totalSupply()
         };
        public func symbol(): async Text { 
            await canister.symbol()
        };
        public func decimals(): async Nat8 { 
            await canister.decimals()
        };
        public func fee(): async Nat { 
            // Debug.print("==>fee-----");
            let metadata = await canister.getMetadata();
            // Debug.print("==>metadata=" # debug_show(metadata));
            metadata.fee;
        };
        public func metadata(): async [(Text, Value)] { 
            let metadata = await canister.getMetadata();
            [
                ("name", #Text(metadata.name)),
                ("symbol", #Text(metadata.symbol)),
                ("decimals", #Nat(Nat8.toNat(metadata.decimals))),
                ("ownerAccount", #Text(PrincipalUtils.toAddress(metadata.owner))),
            ]
        };  
        public func transfer(args: TransferArgs): async TransferResult {
            if (Option.isSome(args.from.subaccount) or Option.isSome(args.from_subaccount) or Option.isSome(args.to.subaccount)) {
                throw Error.reject("transfer: unspported_args_subaccount");
            };
            switch (await canister.transfer(args.to.owner, args.amount)) {
                case (#Ok(index)) { #Ok(index) };
                case (#Err(code)) { throw Error.reject("Reuqest transfer error: " # debug_show(code)) };
            }
        };
        public func approve(args: ApproveArgs): async ApproveResult { 
            switch (await canister.approve(args.spender, args.amount)) {
                case (#Ok(index)) { #Ok(index) };
                case (#Err(code)) { throw Error.reject("Reuqest approve error: " # debug_show(code)) };
            }
        };
        public func transferFrom(args: TransferFromArgs): async TransferFromResult {
            if (Option.isSome(args.from.subaccount) or Option.isSome(args.to.subaccount)) {
                throw Error.reject("transferFrom: unspported_args_subaccount");
            };
            switch (await canister.transferFrom(args.from.owner, args.to.owner, args.amount)) {
                case (#Ok(index)) { #Ok(index) };
                case (#Err(code)) { throw Error.reject("Reuqest transferFrom error: " # debug_show(code)) };
            }
        };
    };
}