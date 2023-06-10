import Text "mo:base/Text";
import Nat8 "mo:base/Nat8";
import Blob "mo:base/Blob";
import Principal "mo:base/Principal";
import Result "mo:base/Result";
import Error "mo:base/Error";
import Option "mo:base/Option";
import PrincipalUtils "mo:commons/utils/PrincipalUtils";
import Types "../../TokenTypes";
import ExtCore "./ext/Core";
import ExtCommon "./ext/Common";
import ExtAllowance "./ext/Allowance";

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


    public class EXTTokenAdapter(cid: Text): Types.TokenAdapter = this {
        let canister = actor(cid): actor { 
            transferFrom: shared (request : ExtCore.TransferRequest) -> async ExtCore.TransferResponse;
            transfer: shared (request : ExtCore.TransferRequest) -> async ExtCore.TransferResponse;
            balance: query (request : ExtCore.BalanceRequest) -> async ExtCore.BalanceResponse;
            getFee: query () -> async Result.Result<ExtCore.Balance, ExtCore.CommonError>;
            approve: shared (request : ExtAllowance.ApproveRequest) -> async Result.Result<Bool, ExtCore.CommonError>;
            metadata: query () -> async Result.Result<ExtCommon.Metadata, ExtCore.CommonError>;
            supply: query () -> async Result.Result<ExtCore.Balance, ExtCore.CommonError>;
            extensions : query () -> async [ExtCore.Extension];
        };
        public func valid(): async Bool {
            try {
                let extensions: [ExtCore.Extension] = await canister.extensions();
                return true;
            } catch(e) {
                return false;
            };
        };
        public func balanceOf(account : Account): async Amount {
            if (Option.isSome(account.subaccount)) {
                throw Error.reject("balanceOf: unspported_args_subaccount");
            };
            let balanceRequest: ExtCore.BalanceRequest = {
                user = #principal(account.owner);
                token = cid;
            };
            switch (await canister.balance(balanceRequest)) {
                case (#ok(balance)) { balance };
                case _ { throw Error.reject("Reuqest balance error.") };
            }
        };
        public func totalSupply(): async Amount { 
            switch (await canister.supply()) {
                case (#ok(supply)) { supply };
                case _ { throw Error.reject("Reuqest totalSupply error.") };
            }
         };
        public func symbol(): async Text { 
            switch (await canister.metadata()) {
                case (#ok(#fungible(metadata))) { metadata.symbol };
                case _ { throw Error.reject("Reuqest symbol error.") };
            }
        };
        public func decimals(): async Nat8 { 
            switch (await canister.metadata()) {
                case (#ok(#fungible(metadata))) { metadata.decimals };
                case _ { throw Error.reject("Reuqest decimals error.") };
            }
        };
        public func fee(): async Nat { 
            switch (await canister.getFee()) {
                case (#ok(fee)) { fee };
                case _ { throw Error.reject("Reuqest fee error.") };
            }
        };
        public func metadata(): async [(Text, Value)] { 
            switch (await canister.metadata()) {
                case (#ok(#fungible(metadata))) { 
                    [
                        ("name", #Text(metadata.name)),
                        ("symbol", #Text(metadata.symbol)),
                        ("decimals", #Nat(Nat8.toNat(metadata.decimals))),
                        ("ownerAccount", #Text(metadata.ownerAccount)),
                    ]
                };
                case _ { throw Error.reject("Reuqest metadata error.") };
            }
        };  
        public func transfer(args: TransferArgs): async TransferResult {
            if (Option.isSome(args.from.subaccount) or Option.isSome(args.from_subaccount) or Option.isSome(args.to.subaccount)) {
                throw Error.reject("transfer: unspported_args_subaccount");
            };
            let _memo = switch(args.memo){ case null{ Blob.fromArray([]); }; case (?memoR){ memoR; }; };
            let _subaccount: ?ExtCore.SubAccount = switch(args.from_subaccount) { case (?subaccount) { ?Blob.toArray(subaccount) }; case null { null }};
            let transferRequest: ExtCore.TransferRequest = {
                from = #principal(args.from.owner);
                to = #principal(args.to.owner);
                token = cid;
                amount = args.amount;
                memo = _memo;
                nonce = null;
                notify = false;
                subaccount = _subaccount;
            };
            switch (await canister.transfer(transferRequest)) {
                case (#ok(amount)) { #Ok(0) };
                case (#err(code)) { throw Error.reject("Reuqest transfer error: " # debug_show(code)) };
            }
        };
        public func approve(args: ApproveArgs): async ApproveResult {
            let _subaccount: ?ExtCore.SubAccount = switch(args.from_subaccount) { case (?subaccount) { ?Blob.toArray(subaccount) }; case null { null }};
            let approveArgs: ExtAllowance.ApproveRequest = {
                subaccount = _subaccount;
                spender = args.spender;
                allowance = args.amount;
            };
            switch (await canister.approve(approveArgs)) {
                case (#ok(amount)) { #Ok(0) };
                case (#err(code)) { throw Error.reject("Reuqest approve error: " # debug_show(code)) };
            }
        };
        public func transferFrom(args: TransferFromArgs): async TransferFromResult {
            if (Option.isSome(args.from.subaccount) or Option.isSome(args.to.subaccount)) {
                throw Error.reject("transferFrom: unspported_args_subaccount");
            };
            var _memo = switch(args.memo){ case null{ Blob.fromArray([]); }; case (?memoR){ memoR; }; };
            let _subaccount: ?ExtCore.SubAccount = switch(args.from.subaccount) { case (?subaccount) { ?Blob.toArray(subaccount) }; case null { null }};
            let transferRequest: ExtCore.TransferRequest = {
                from = #principal(args.from.owner);
                to = #principal(args.to.owner);
                token = cid;
                amount = args.amount;
                memo = _memo;
                nonce = null;
                notify = false;
                subaccount = _subaccount;
            };
            switch (await canister.transferFrom(transferRequest)) {
                case (#ok(amount)) { #Ok(0) };
                case (#err(code)) { throw Error.reject("Reuqest transferFrom error: " # debug_show(code)) };
            }
        };
    };
}