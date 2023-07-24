import Int "mo:base/Int";
import Nat "mo:base/Nat";
import Bool "mo:base/Bool";
import Iter "mo:base/Iter";
import Text "mo:base/Text";
import Time "mo:base/Time";
import Order "mo:base/Order";
import Debug "mo:base/Debug";
import Error "mo:base/Error";
import Array "mo:base/Array";
import Buffer "mo:base/Buffer";
import Option "mo:base/Option";
import HashMap "mo:base/HashMap";
import Principal "mo:base/Principal";
import ExperimentalCycles "mo:base/ExperimentalCycles";

import TextUtil "mo:commons/TextUtils";
import ListUtil "mo:commons/CollectUtils";
import PrincipalUtil "mo:commons/PrincipalUtils";

import Launchpad "./Launchpad";
import LaunchpadCanister "./LaunchpadCanister";
import CommonModel "./commons/CommonModel";
import LaunchpadUtil "./commons/LaunchpadUtil";
import CanisterModel "./commons/CanisterModel";
import AccountUtils "./commons/AccountUtils";
import TokenFactory "./token/TokenFactory";

import LaunchpadStorage "canister:LaunchpadStorage";

actor class LaunchpadManager() : async Launchpad.LaunchpadManager = this {

    private let _initCycles : Nat = 1860000000000;

    private stable var installed : Bool = false;
    private stable var canisterArry : [CanisterModel.CanisterView] = [];
    private let canisters : Buffer.Buffer<CanisterModel.CanisterView> = Buffer.Buffer<CanisterModel.CanisterView>(0);
    private stable var launchpadCanisterArry : [Launchpad.LaunchpadCanister] = [];
    private let launchpadCanisters : Buffer.Buffer<Launchpad.LaunchpadCanister> = Buffer.Buffer<Launchpad.LaunchpadCanister>(0);
    private stable var ticketEntries : [(Text, Text)] = [];
    // Map(address: Text, ticket: Text)
    private let ticketMap : HashMap.HashMap<Text, Text> = HashMap.fromIter<Text, Text>(ticketEntries.vals(), 10, Text.equal, Text.hash);
    private var launchpadCanisterEntries : [(Text, Buffer.Buffer<Text>)] = [];
    // Map(cid: Text, tickets: Buffer.Buffer<Text>)
    private let routeCanisterMap : HashMap.HashMap<Text, Buffer.Buffer<Text>> = HashMap.fromIter<Text, Buffer.Buffer<Text>>(launchpadCanisterEntries.vals(), 10, Text.equal, Text.hash);
    private stable var launchpadDetail : ?Launchpad.Property = null;
    private stable var uniqueTicket : Text = "";
    private stable var whitelist : [Text] = [];
    // private stable var pricingTokenCanister: ?Token.IToken = null;
    private stable var finalTokenSet : ?Launchpad.TokenSet = null;
    private stable var fundraisingTotalPricingTokenQuantity : ?Text = null;

    private let ic00 = actor "aaaaa-aa" : actor {
        update_settings : {
            canister_id : Principal;
            settings : { controllers : [Principal] };
        } -> async ();
        stop_canister : { canister_id : Principal } -> async ();
        delete_canister : { canister_id : Principal } -> async ();
    };

    // It will generate `CANISTER_NUMBER` or `prop.canisterQuantity` Launchpad canister to handle operation of investors When installation
    public shared func install(owner : Principal, prop : Launchpad.Property, wl : [Text]) : async CommonModel.ResponseResult<Launchpad.Property> {
        if (installed) {
            throw Error.reject("launchpad_manager_canister_has_been_installed");
        };

        if (Principal.isAnonymous(owner)) return #err("Illegal anonymous call");
        var subaccount : ?Blob = Option.make(AccountUtils.principalToBlob(owner));
        if (null == subaccount) {
            return #err("Subaccount can't be null");
        };

        if (Text.notEqual(prop.soldTokenStandard, "ICP") and Text.notEqual(prop.soldTokenStandard, "ICRC1") and Text.notEqual(prop.soldTokenStandard, "ICRC2")) {
            return #err("Illegal token standard: " # debug_show (prop.soldTokenStandard));
        };

        var canisterPrincipal = Principal.fromActor(this);
        let soldTokenAdapter = TokenFactory.getAdapter(prop.soldTokenId, prop.soldTokenStandard);
        var balance : Nat = await soldTokenAdapter.balanceOf({
            owner = canisterPrincipal;
            subaccount = subaccount;
        });
        if (not (balance > 0)) {
            return #err("The amount of add can’t be 0");
        };
        let tokenTransFee = await LaunchpadUtil.getFee(prop.soldTokenId, prop.soldTokenStandard);
        if (not (balance > tokenTransFee)) {
            return #err("The amount of add is less than the token transfer fee");
        };
        var expectedSellQuantity : Nat = balance;

        let canisterAddress : Text = PrincipalUtil.toAddress(canisterPrincipal);
        let creatorAddress : Text = PrincipalUtil.toAddress(owner);
        ignore await transferToken(canisterPrincipal, subaccount, canisterPrincipal, null, expectedSellQuantity, tokenTransFee, prop.soldTokenId, prop.soldTokenStandard);
        let now : Time.Time = Time.now();
        launchpadDetail := ?{
            id = canisterAddress;
            cid = PrincipalUtil.toText(canisterPrincipal);
            name = prop.name;
            description = prop.description;
            startDateTime = prop.startDateTime;
            endDateTime = prop.endDateTime;
            depositDateTime = ?now;
            withdrawalDateTime = prop.withdrawalDateTime;
            soldTokenId = prop.soldTokenId;
            soldTokenStandard = prop.soldTokenStandard;
            pricingTokenId = prop.pricingTokenId;
            pricingTokenStandard = prop.pricingTokenStandard;
            initialExchangeRatio = prop.initialExchangeRatio;
            soldQuantity = prop.soldQuantity;
            depositedQuantity = prop.depositedQuantity;
            expectedSellQuantity = prop.expectedSellQuantity;
            extraTokenFee = prop.extraTokenFee;
            fundraisingPricingTokenQuantity = prop.fundraisingPricingTokenQuantity;
            expectedFundraisingPricingTokenQuantity = TextUtil.fromNat(await LaunchpadUtil.getPricingTokenQuantityByTokenQuantity(TextUtil.toNat(prop.expectedSellQuantity), TextUtil.toNat(prop.initialExchangeRatio), prop.soldTokenId, prop.soldTokenStandard, prop.pricingTokenId, prop.pricingTokenStandard));
            limitedAmountOnce = prop.limitedAmountOnce;
            receiveTokenDateTime = prop.receiveTokenDateTime;
            creator = creatorAddress;
            creatorPrincipal = owner;
            createdDateTime = now;
            settled = ?false;
            canisterQuantity = prop.canisterQuantity;
        };
        whitelist := wl;
        // install launchpad canister list
        var index : Nat = 0;
        label generationLaunchpad while (true) {
            ExperimentalCycles.add(_initCycles); // pay for the cycle fee
            let canister : Launchpad.LaunchpadCanister = await LaunchpadCanister.LaunchpadCanister();
            await _setController(
                Principal.fromActor(canister),
                Principal.fromText(LaunchpadUtil.WALLET_CANISTER_ID),
                owner,
            );
            ignore await canister.install(prop, canisterAddress, whitelist);
            launchpadCanisters.add(canister);
            let cid : Text = PrincipalUtil.toText(Principal.fromActor(canister));
            routeCanisterMap.put(cid, Buffer.Buffer<Text>(0));

            let canisterView : CanisterModel.CanisterView = {
                id = cid;
                name = "Launchpad(" # prop.name # "_" # TextUtil.fromNat(index) # ")";
                cycle = 0;
            };
            canisters.add(canisterView);

            index += 1;
            if (index == prop.canisterQuantity) {
                break generationLaunchpad;
            };
        };
        installed := true;
        #ok(await LaunchpadUtil.getLaunchpadDetail(launchpadDetail));
    };

    // Get detail of launchpad
    public query func getDetail() : async CommonModel.ResponseResult<Launchpad.Property> {
        switch (launchpadDetail) {
            case (?prop) {
                #ok(prop);
            };
            case (_) {
                throw Error.reject("The launchpad property is null.");
            };
        };
    };

    public query func getWhitelistSize() : async Nat {
        return whitelist.size();
    };

    public query func getWhitelist(offset : Nat, limit : Nat) : async CommonModel.ResponseResult<CommonModel.Page<Text>> {
        let result : [Text] = ListUtil.arrayRange<Text>(whitelist, offset, limit);
        return #ok({
            totalElements = whitelist.size();
            content = result;
            offset = offset;
            limit = limit;
        });
    };

    public shared (msg) func withdraw() : async CommonModel.ResponseResult<Launchpad.TokenSet> {
        let launchpad : Launchpad.Property = await LaunchpadUtil.getLaunchpadDetail(launchpadDetail);
        let now : Time.Time = Time.now();
        if (now > launchpad.endDateTime) {
            if (Option.get<Bool>(launchpad.settled, false)) {
                switch (launchpad.withdrawalDateTime) {
                    case (?withdrawalDateTime) {
                        return #err("The_launchpad_had_been_withdrawn");
                    };
                    case (_) {
                        let ownerFinalTokenSet : Launchpad.TokenSet = Option.get<Launchpad.TokenSet>(finalTokenSet, LaunchpadUtil.defaultTokenSet);
                        Debug.print("ownerFinalTokenSet.pricingToken.quantity: " # ownerFinalTokenSet.pricingToken.quantity);
                        let managerAddress : Text = PrincipalUtil.toAddress(Principal.fromActor(this));
                        let pricingTokenTransFee : Nat = await LaunchpadUtil.getFee(launchpad.pricingTokenId, launchpad.pricingTokenStandard);
                        // if (TextUtil.toNat(ownerFinalTokenSet.pricingToken.quantity) > pricingTokenTransFee) {
                        // manager canister --pricingToken--> owner
                        let tokenAdapter = TokenFactory.getAdapter(launchpad.pricingTokenId, launchpad.pricingTokenStandard);
                        var balance : Nat = 0;
                        try {
                            balance := await tokenAdapter.balanceOf({
                                owner = Principal.fromActor(this);
                                subaccount = null;
                            });
                        } catch (e) {
                            throw Error.reject(Error.message(e));
                        };
                        if (balance > pricingTokenTransFee) {
                            if (await transferByToAddress(launchpad.creatorPrincipal, balance - pricingTokenTransFee, launchpad.pricingTokenId, launchpad.pricingTokenStandard)) {
                                await LaunchpadStorage.addTransaction(
                                    managerAddress,
                                    {
                                        managerAddress = managerAddress;
                                        launchpadAddress = launchpad.id;
                                        time = now;
                                        operationType = "withdraw";
                                        tokenName = ownerFinalTokenSet.pricingToken.name;
                                        tokenSymbol = ownerFinalTokenSet.pricingToken.symbol;
                                        quantity = TextUtil.fromNat(balance - pricingTokenTransFee);
                                        address = managerAddress;
                                    },
                                );
                            };
                        };

                        // };
                        Debug.print("pricingToken.balance: " # TextUtil.fromNat(balance));

                        let tokenTransFee : Nat = await LaunchpadUtil.getFee(launchpad.soldTokenId, launchpad.soldTokenStandard);
                        Debug.print("ownerFinalTokenSet.token.quantity: " # ownerFinalTokenSet.token.quantity);
                        if (TextUtil.toNat(ownerFinalTokenSet.token.quantity) > tokenTransFee) {
                            // manager canister --token--> owner
                            let tokenAdapter = TokenFactory.getAdapter(launchpad.soldTokenId, launchpad.soldTokenStandard);
                            var balance : Nat = 0;
                            try {
                                balance := await tokenAdapter.balanceOf({
                                    owner = Principal.fromActor(this);
                                    subaccount = null;
                                });
                            } catch (e) {
                                throw Error.reject(Error.message(e));
                            };
                            Debug.print("soldToken.balance: " # TextUtil.fromNat(balance));
                            if (await transferByToAddress(launchpad.creatorPrincipal, balance - tokenTransFee, launchpad.soldTokenId, launchpad.soldTokenStandard)) {
                                await LaunchpadStorage.addTransaction(
                                    managerAddress,
                                    {
                                        managerAddress = managerAddress;
                                        launchpadAddress = launchpad.id;
                                        time = now;
                                        operationType = "withdraw";
                                        tokenName = ownerFinalTokenSet.token.name;
                                        tokenSymbol = ownerFinalTokenSet.token.symbol;
                                        quantity = TextUtil.fromNat(balance - tokenTransFee);
                                        address = managerAddress;
                                    },
                                );
                            };
                        };
                        launchpadDetail := ?{
                            id = launchpad.id;
                            cid = launchpad.cid;
                            name = launchpad.name;
                            description = launchpad.description;
                            startDateTime = launchpad.startDateTime;
                            endDateTime = launchpad.endDateTime;
                            depositDateTime = launchpad.depositDateTime;
                            withdrawalDateTime = ?Time.now();
                            soldTokenId = launchpad.soldTokenId;
                            soldTokenStandard = launchpad.soldTokenStandard;
                            pricingTokenId = launchpad.pricingTokenId;
                            pricingTokenStandard = launchpad.pricingTokenStandard;
                            initialExchangeRatio = launchpad.initialExchangeRatio;
                            soldQuantity = launchpad.soldQuantity;
                            depositedQuantity = launchpad.depositedQuantity;
                            expectedSellQuantity = launchpad.expectedSellQuantity;
                            extraTokenFee = launchpad.extraTokenFee;
                            fundraisingPricingTokenQuantity = launchpad.fundraisingPricingTokenQuantity;
                            expectedFundraisingPricingTokenQuantity = launchpad.expectedFundraisingPricingTokenQuantity;
                            limitedAmountOnce = launchpad.limitedAmountOnce;
                            receiveTokenDateTime = launchpad.receiveTokenDateTime;
                            creator = launchpad.creator;
                            creatorPrincipal = launchpad.creatorPrincipal;
                            createdDateTime = launchpad.createdDateTime;
                            settled = ?true;
                            canisterQuantity = launchpad.canisterQuantity;
                        };
                        return #ok(ownerFinalTokenSet);
                    };
                };
            };
            return #err("The_launchpad_had_been_settled");
        };
        return #err("The_time_of_launchpad_has_not_end_yet");
    };

    public query func inWhitelist(userAddress : Text) : async CommonModel.BoolResult {
        return #ok(isInWhitelist(userAddress));
    };

    private func isInWhitelist(userAddress : Text) : Bool {
        if (whitelist.size() == 0) {
            return true;
        };
        return ListUtil.arrayContains<Text>(whitelist, userAddress, Text.equal);
    };

    // We use the lock to generate tickets.
    // Avoid multiple same tickets generation when parallel calling.
    private func _generateTicket(userAddress : Text) : async Text {
        // try {
        //   await Lock.lock("launchpad_generated_ticket");
        //   uniqueTicket := TextUtil.nat2Text(TextUtil.textToNat(uniqueTicket) + 1);
        //   await Lock.unlock("launchpad_generated_ticket");
        // } catch (e) {
        //   await Lock.unlock("launchpad_generated_ticket");
        // };
        // return uniqueTicket;
        return "tk_" # userAddress; // The ticket we can use the user address as unique.
    };

    // Generate ticket for every investor.
    // This ticket is used for routing to a one of launchpad canisters.
    public shared func generateTicket(userAddress : Text) : async CommonModel.ResponseResult<Text> {
        if (isInWhitelist(userAddress)) {
            switch (ticketMap.get(userAddress)) {
                case (?ticket) {
                    return #ok(ticket);
                };
                case (_) {
                    let newTicket : Text = await _generateTicket(userAddress);
                    let cid : Text = routeLaunchpadCanister(newTicket);
                    ticketMap.put(userAddress, newTicket);
                    let canister : Launchpad.LaunchpadCanister = actor (cid) : Launchpad.LaunchpadCanister;
                    await canister.addInvestorAddress(userAddress);
                    return #ok(newTicket);
                };
            };
        } else {
            return #err("Out_of_the_investor_whitelist");
        };
    };

    // Routing to a one of launchpad canisters via the ticket.
    // The strategy is to route to the canister which has less ticket.
    private func routeLaunchpadCanister(ticket : Text) : Text {
        var size : Nat = 0;
        type CidNSize = {
            cid : Text;
            size : Nat;
        };
        var cidNSize : Buffer.Buffer<CidNSize> = Buffer.Buffer<CidNSize>(0);
        for (cid in routeCanisterMap.keys()) {
            cidNSize.add({
                cid = cid;
                size = getTickets(cid).size();
            });
        };
        let ascSortedArry : [CidNSize] = Array.sort(
            cidNSize.toArray(),
            func(a : CidNSize, b : CidNSize) : Order.Order {
                if (a.size > b.size) {
                    return #greater;
                } else if (a.size == b.size) {
                    return #equal;
                } else {
                    return #less;
                };
            },
        );
        let targetCid : Text = ascSortedArry[0].cid;
        let tickets : Buffer.Buffer<Text> = getTickets(targetCid);
        tickets.add(ticket);
        return targetCid;
    };

    private func getCidByTicket(ticket : Text) : Text {
        for (cid in routeCanisterMap.keys()) {
            let tickets : Buffer.Buffer<Text> = getTickets(cid);
            if (ListUtil.arrayContains<Text>(tickets.toArray(), ticket, Text.equal)) {
                return cid;
            };
        };
        // throw Error.reject("The_ticket_" # ticket # "_does_not_exist");
        return "";
    };

    // Get tickets corresponding to the cid
    private func getTickets(cid : Text) : Buffer.Buffer<Text> {
        switch (routeCanisterMap.get(cid)) {
            case (?tickets) {
                return tickets;
            };
            case (_) {
                // throw Error.reject("The_cid_" # cid # "_does_not_exist");
                return Buffer.Buffer<Text>(0);
            };
        };
    };

    public query (msg) func getTicketPackage(userAddress : Text, ticket : Text) : async CommonModel.ResponseResult<Launchpad.TicketPackage> {
        if (isInWhitelist(userAddress)) {
            return #ok({
                ticket = ticket;
                cid = getCidByTicket(ticket);
            });
        } else {
            return #err("Out_of_the_investor_whitelist");
        };
    };

    private func _getPricingTokenQuantity() : async Text {
        var pricingTokenQuantity : Nat = 0;
        for (canister in launchpadCanisters.vals()) {
            pricingTokenQuantity += LaunchpadUtil.getValue<Nat>(await canister.getPricingTokenQuantity(), 0);
        };
        return TextUtil.fromNat(pricingTokenQuantity);
    };

    public shared func getPricingTokenQuantity() : async CommonModel.ResponseResult<Text> {
        return #ok(Option.get<Text>(fundraisingTotalPricingTokenQuantity, await _getPricingTokenQuantity()));
    };

    public shared func getInvestorsSize() : async CommonModel.ResponseResult<Nat> {
        var size : Nat = 0;
        for (canister in launchpadCanisters.vals()) {
            size += await canister.getInvestorsSize();
        };
        return #ok(size);
    };

    private func transferToken(fromPrincipal : Principal, fromSubAccount : ?Blob, toPrincipal : Principal, toSubAccount : ?Blob, tokenQuantity : Nat, transFee : Nat, tokenCid : Text, tokenStandard : Text) : async Nat {
        let canisterAddress : Text = PrincipalUtil.toAddress(toPrincipal);
        let investorAddress : Text = PrincipalUtil.toAddress(fromPrincipal);
        let tokenAdapter = TokenFactory.getAdapter(tokenCid, tokenStandard);
        if (tokenQuantity > transFee) {
            var transferTokenQuantity = Nat.sub(tokenQuantity, transFee);
            var params = {
                from = {
                    owner = fromPrincipal;
                    subaccount = fromSubAccount;
                };
                from_subaccount = fromSubAccount;
                to = {
                    owner = toPrincipal;
                    subaccount = toSubAccount;
                };
                fee = null;
                amount = transferTokenQuantity;
                memo = null;
                created_at_time = null;
            };
            if (Principal.toText(fromPrincipal) == Principal.toText(Principal.fromActor(this))) {
                switch (await tokenAdapter.transfer(params)) {
                    case (#Ok(index)) {
                        Debug.print("transfer from " # Principal.toText(fromPrincipal) # " to " # Principal.toText(toPrincipal) # ", params: " # debug_show (params) # ", token: PricingToken, amountPrefee: " # TextUtil.fromNat(transferTokenQuantity));
                        return transferTokenQuantity;
                    };
                    case (#Err(code)) {
                        throw Error.reject("transfer from " # Principal.toText(fromPrincipal) # "_2_canister_failed: " # debug_show (code) # ", params:" # debug_show (params));
                    };
                };
            } else {
                switch (await tokenAdapter.transferFrom(params)) {
                    case (#Ok(index)) {
                        Debug.print("transfer from \"" # investorAddress # "\" to \"" # canisterAddress # "\", amount: " # debug_show (transferTokenQuantity) # ", token: PricingToken, amountPrefee: " # TextUtil.fromNat(transferTokenQuantity));
                        return transferTokenQuantity;
                    };
                    case (#Err(code)) {
                        let description : Text = "{transaction: {from: \"" # investorAddress # "\", to: \"" # canisterAddress # "\", value: " # TextUtil.fromNat(transferTokenQuantity) # ", token: \"PricingToken\", description: \"investor --pricingToken--> Launchpad Canister(" # canisterAddress # ")\"}}";
                        throw Error.reject("tarsnfer_from_investor(" # investorAddress # ")_2_canister_failed: " # debug_show (code) # ", " # description);
                    };
                };
            };
        } else {
            throw Error.reject("Your_token(" # TextUtil.fromNat(tokenQuantity) # ")_is_lower_than_trans_fee(" # TextUtil.fromNat(transFee) # ")");
        };
    };

    // from address --token--> Launchpad manager Canister
    // private func transferByFromAddress(fromPrincipal : Principal, tokenQuantity : Nat, tokenCid : Text, tokenStandard : Text) : async Nat {
    //     let fromAddress : Text = PrincipalUtil.toAddress(fromPrincipal);
    //     let canisterAddress : Text = LaunchpadUtil.getCanisterAddress(this);
    //     let tokenAdapter = TokenFactory.getAdapter(tokenCid, tokenStandard);
    //     var transFee : Nat = 0;
    //     try {
    //         let transFee : Nat = await tokenAdapter.fee();
    //     } catch (e) {
    //         throw Error.reject(Error.message(e));
    //     };
    //     var params = {
    //         from = { owner = fromPrincipal; subaccount = null };
    //         from_subaccount = null;
    //         to = {
    //             owner = LaunchpadUtil.getCanisterPrincipal(this);
    //             subaccount = null;
    //         };
    //         fee = null;
    //         amount = tokenQuantity;
    //         memo = null;
    //         created_at_time = null;
    //     };
    //     switch (await tokenAdapter.transferFrom(params)) {
    //         case (#Ok(index)) {
    //             Debug.print("transfer from \"" # fromAddress # "\" to \"" # canisterAddress # "\", amount: " # debug_show (tokenQuantity) # ", token: Token, amountPrefee: " # TextUtil.fromNat(tokenQuantity - transFee));
    //             return tokenQuantity - transFee;
    //         };
    //         case (#Err(code)) {
    //             let description : Text = "{transaction: {from: \"" # fromAddress # "\", to: \"" # canisterAddress # "\", value: " # TextUtil.fromNat(tokenQuantity) # ", token: \"" # tokenCid # "\"}}";
    //             throw Error.reject("tarsnfer_from_address(" # fromAddress # ")_to_manager_canister(" # canisterAddress # ")_failed: " # debug_show (code) # ", " # description);
    //         };
    //     };
    //     return tokenQuantity;
    // };

    // Launchpad manager Canister --token--> destination address
    private func transferByToAddress(destinationPrincipal : Principal, tokenQuantity : Nat, tokenCid : Text, tokenStandard : Text) : async Bool {
        let destinationAddress : Text = PrincipalUtil.toAddress(destinationPrincipal);
        let canisterAddress : Text = LaunchpadUtil.getCanisterAddress(this);
        let tokenAdapter = TokenFactory.getAdapter(tokenCid, tokenStandard);
        var transFee : Nat = 0;
        try {
            let transFee : Nat = await tokenAdapter.fee();
        } catch (e) {
            throw Error.reject(Error.message(e));
        };
        var params = {
            from = { owner = Principal.fromActor(this); subaccount = null };
            from_subaccount = null;
            to = {
                owner = destinationPrincipal;
                subaccount = null;
            };
            fee = null;
            amount = tokenQuantity;
            memo = null;
            created_at_time = null;
        };
        let description : Text = "{transaction: {from: \"" # canisterAddress # "\", to: \"" # destinationAddress # "\", value: " # TextUtil.fromNat(tokenQuantity) # ", token: \"" # tokenCid # "\"}}";
        switch (await tokenAdapter.transfer(params)) {
            case (#Ok(index)) {
                Debug.print("Transfer success: " # description);
                return true;
            };
            case (#Err(code)) {
                throw Error.reject("tarsnfer_from_manager_canister(" # canisterAddress # ")_to_destination(" # destinationAddress # ")_failed: " # debug_show (code) # ", " # description);
            };
        };
        return false;
    };

    public shared func settle() : async CommonModel.BoolResult {
        let launchpad : Launchpad.Property = await LaunchpadUtil.getLaunchpadDetail(launchpadDetail);
        if (launchpad.endDateTime < Time.now()) {
            switch (finalTokenSet) {
                case (null) {
                    fundraisingTotalPricingTokenQuantity := ?(await _getPricingTokenQuantity());
                    Debug.print("fundraisingTotalPricingTokenQuantity: " # debug_show (fundraisingTotalPricingTokenQuantity));
                    Debug.print("initialExchangeRatio: " # debug_show (launchpad.initialExchangeRatio));
                    // Real fund raising token quantity
                    let fundraisingTotalTokenQuantity : Nat = await LaunchpadUtil.getTokenQuantityByPricingTokenQuantity(TextUtil.toNat(Option.get<Text>(fundraisingTotalPricingTokenQuantity, "0")), TextUtil.toNat(launchpad.initialExchangeRatio), launchpad.soldTokenId, launchpad.soldTokenStandard, launchpad.pricingTokenId, launchpad.pricingTokenStandard);
                    let expectedSellQuantity : Nat = TextUtil.toNat(launchpad.expectedSellQuantity);
                    Debug.print("fundraisingTotalTokenQuantity: " # debug_show (fundraisingTotalTokenQuantity));
                    Debug.print("expectedSellQuantity: " # debug_show (expectedSellQuantity));
                    var totalPricingTokenQuantity : Nat = 0;
                    var totalTokenQuantity : Nat = 0;
                    var pricingTokenInfo : Launchpad.TokenInfo = LaunchpadUtil.defaultTokenInfo;
                    var tokenInfo : Launchpad.TokenInfo = LaunchpadUtil.defaultTokenInfo;
                    var extraTokenFee : Nat = Option.get<Nat>(launchpad.extraTokenFee, 0);
                    Debug.print("before extraTokenFee: " # debug_show (extraTokenFee));
                    for (launchpadCanister in launchpadCanisters.vals()) {
                        let eachLaunchpadFinalTokenViewSet : Launchpad.TokenViewSet = await launchpadCanister.computeFinalTokenViewSet(expectedSellQuantity, fundraisingTotalTokenQuantity);

                        if (pricingTokenInfo.name == "") {
                            pricingTokenInfo := eachLaunchpadFinalTokenViewSet.pricingToken.info;
                        };
                        if (tokenInfo.name == "") {
                            tokenInfo := eachLaunchpadFinalTokenViewSet.token.info;
                        };

                        let launchpadCanisterAddress : Text = LaunchpadUtil.getCanisterAddress(launchpadCanister);
                        let launchpadCanisterPrincipal : Principal = LaunchpadUtil.getCanisterPrincipal(launchpadCanister);

                        let eachLaunchpadPricingTokenQuantity : Nat = TextUtil.toNat(eachLaunchpadFinalTokenViewSet.pricingToken.info.quantity);
                        Debug.print("eachLaunchpadPricingTokenQuantity: " # debug_show (eachLaunchpadPricingTokenQuantity));
                        if (eachLaunchpadPricingTokenQuantity > 0) {
                            Debug.print("start super raisefunding......");
                            if (eachLaunchpadPricingTokenQuantity >= eachLaunchpadFinalTokenViewSet.pricingToken.transFee) {
                                ignore await launchpadCanister.transferByAddress(launchpadCanisterPrincipal, LaunchpadUtil.getCanisterPrincipal(this), eachLaunchpadPricingTokenQuantity, launchpad.pricingTokenId, launchpad.pricingTokenStandard);
                                Debug.print("launchpad -pricingToken-> manager canister");
                                Debug.print("eachLaunchpadPricingTokenQuantity: " # debug_show (eachLaunchpadPricingTokenQuantity));
                                Debug.print("eachLaunchpadFinalTokenViewSet.pricingToken.transFee: " # debug_show (eachLaunchpadFinalTokenViewSet.pricingToken.transFee));
                                totalPricingTokenQuantity += eachLaunchpadPricingTokenQuantity;
                            };

                            let eachLaunchpadTokenQuantity : Nat = TextUtil.toNat(eachLaunchpadFinalTokenViewSet.token.info.quantity);

                            let soldTokenTransFee : Nat = await LaunchpadUtil.getFee(launchpad.soldTokenId, launchpad.soldTokenStandard);

                            if (eachLaunchpadTokenQuantity > 0) {
                                if (eachLaunchpadTokenQuantity > soldTokenTransFee) {
                                    // manager canister -token-> launchpad canister
                                    ignore await transferByToAddress(launchpadCanisterPrincipal, eachLaunchpadTokenQuantity, launchpad.soldTokenId, launchpad.soldTokenStandard);
                                };
                                extraTokenFee -= eachLaunchpadFinalTokenViewSet.token.transFee;
                                Debug.print("manager canister -token-> launchpad");
                                Debug.print("eachLaunchpadTokenQuantity: " # debug_show (eachLaunchpadTokenQuantity));
                                Debug.print("eachLaunchpadFinalTokenViewSet.token.transFee: " # debug_show (eachLaunchpadFinalTokenViewSet.token.transFee));
                                totalTokenQuantity += eachLaunchpadTokenQuantity;
                            };
                        };
                    };
                    Debug.print("totalPricingTokenQuantity: " # debug_show (totalPricingTokenQuantity));
                    Debug.print("reset token quantity: " # " expectedSellQuantity: " # launchpad.expectedSellQuantity # ", totalTokenQuantity: " # debug_show (totalTokenQuantity));
                    Debug.print("totalTokenQuantity: " # debug_show (totalTokenQuantity));
                    Debug.print("after extraTokenFee: " # debug_show (extraTokenFee));
                    finalTokenSet := ?{
                        pricingToken = {
                            name = pricingTokenInfo.name;
                            symbol = pricingTokenInfo.symbol;
                            logo = pricingTokenInfo.logo;
                            quantity = TextUtil.fromNat(totalPricingTokenQuantity);
                        };
                        token = {
                            name = tokenInfo.name;
                            symbol = tokenInfo.symbol;
                            logo = tokenInfo.logo;
                            quantity = TextUtil.fromNat(TextUtil.toNat(launchpad.expectedSellQuantity) - totalTokenQuantity + extraTokenFee);
                        };
                    };
                    launchpadDetail := ?{
                        id = launchpad.id;
                        cid = launchpad.cid;
                        name = launchpad.name;
                        description = launchpad.description;
                        startDateTime = launchpad.startDateTime;
                        endDateTime = launchpad.endDateTime;
                        depositDateTime = launchpad.depositDateTime;
                        withdrawalDateTime = launchpad.withdrawalDateTime;
                        soldTokenId = launchpad.soldTokenId;
                        soldTokenStandard = launchpad.soldTokenStandard;
                        pricingTokenId = launchpad.pricingTokenId;
                        pricingTokenStandard = launchpad.pricingTokenStandard;
                        initialExchangeRatio = launchpad.initialExchangeRatio;
                        soldQuantity = launchpad.soldQuantity;
                        depositedQuantity = launchpad.depositedQuantity;
                        expectedSellQuantity = launchpad.expectedSellQuantity;
                        extraTokenFee = ?extraTokenFee;
                        fundraisingPricingTokenQuantity = launchpad.fundraisingPricingTokenQuantity;
                        expectedFundraisingPricingTokenQuantity = launchpad.expectedFundraisingPricingTokenQuantity;
                        limitedAmountOnce = launchpad.limitedAmountOnce;
                        receiveTokenDateTime = launchpad.receiveTokenDateTime;
                        creator = launchpad.creator;
                        creatorPrincipal = launchpad.creatorPrincipal;
                        createdDateTime = launchpad.createdDateTime;
                        settled = ?true;
                        canisterQuantity = launchpad.canisterQuantity;
                    };
                    await LaunchpadStorage.addSettledLaunchpad(await LaunchpadUtil.getLaunchpadDetail(launchpadDetail));
                    #ok(true);
                };
                case (_) {
                    #err("You have settle already, the duplicated operation.");
                };
            };
        } else {
            #err("The_time_is_out_of_bounds");
        };
    };

    public func archive() : async () {
        let launchpad : Launchpad.Property = await LaunchpadUtil.getLaunchpadDetail(launchpadDetail);
        let settled = Option.get<Bool>(launchpad.settled, false);
        Debug.print("launchpad.settled: " # debug_show (settled));
        if (settled) {
            let needToBeRemoved : Buffer.Buffer<Launchpad.LaunchpadCanister> = Buffer.Buffer<Launchpad.LaunchpadCanister>(0);
            let needToBeRemovedCanisterView : Buffer.Buffer<CanisterModel.CanisterView> = Buffer.Buffer<CanisterModel.CanisterView>(0);
            var index : Nat = 0;
            for (launchpadCanister in launchpadCanisters.vals()) {
                var allDone : Bool = true; // all of investors have been withdrawn
                Debug.print("(await launchpadCanister.getInvestors()).size(): " # debug_show ((await launchpadCanister.getInvestors()).size()));
                if ((await launchpadCanister.getInvestors()).size() > 0) {
                    label loopInvestors for (investor in (await launchpadCanister.getInvestors()).vals()) {
                        Debug.print("investor: " # debug_show (investor.id));
                        Debug.print("investor.withdrawalDateTime: " # debug_show (investor.withdrawalDateTime));
                        if (investor.withdrawalDateTime == null) {
                            allDone := false;
                            break loopInvestors;
                        };
                    };
                };
                Debug.print("allDone: " # debug_show (allDone));
                if (allDone) {
                    needToBeRemoved.add(launchpadCanister);
                    needToBeRemovedCanisterView.add(canisters.get(index));
                    await destroyCanister(Principal.fromActor(launchpadCanister));
                };
                index += 1;
            };
            Debug.print("needToBeRemoved size: " # debug_show (needToBeRemoved.size()));
            ignore bufferRemoveMultiple<Launchpad.LaunchpadCanister>(
                launchpadCanisters,
                needToBeRemoved,
                func(a : Launchpad.LaunchpadCanister, b : Launchpad.LaunchpadCanister) : Bool {
                    return PrincipalUtil.toAddress(Principal.fromActor(a)) == PrincipalUtil.toAddress(Principal.fromActor(b));
                },
            );
            Debug.print("needToBeRemovedCanisterView size: " # debug_show (needToBeRemovedCanisterView.size()));
            ignore bufferRemoveMultiple<CanisterModel.CanisterView>(
                canisters,
                needToBeRemovedCanisterView,
                func(a : CanisterModel.CanisterView, b : CanisterModel.CanisterView) : Bool {
                    return a.id == b.id;
                },
            );
        };
        Debug.print("launchpadCanisters size: " # debug_show (launchpadCanisters.size()));
    };

    private func bufferRemove<T>(buf : Buffer.Buffer<T>, item : T, equal : (T, T) -> Bool) : Buffer.Buffer<T> {
        let tempBuff : Buffer.Buffer<T> = Buffer.Buffer<T>(0);
        while (buf.size() > 0) {
            switch (buf.removeLast()) {
                case null {};
                case (?bi) {
                    if (not equal(bi, item)) {
                        tempBuff.add(bi);
                    };
                };
            };
        };
        while (tempBuff.size() > 0) {
            switch (tempBuff.removeLast()) {
                case null {};
                case (?tbi) {
                    buf.add(tbi);
                };
            };
        };
        return buf;
    };

    private func bufferRemoveMultiple<T>(buf : Buffer.Buffer<T>, items : Buffer.Buffer<T>, equal : (T, T) -> Bool) : Buffer.Buffer<T> {
        while (items.size() > 0) {
            switch (items.removeLast()) {
                case null {};
                case (?item) {
                    ignore bufferRemove<T>(buf, item, equal);
                };
            };
        };
        return buf;
    };

    // @see {@link https://smartcontracts.org/docs/interface-spec/index.html#ic-delete_canister}
    private func destroyCanister(canisterId : Principal) : async () {
        await ic00.stop_canister({
            canister_id = canisterId;
        });
        await ic00.delete_canister({
            canister_id = canisterId;
        });
    };

    public shared (msg) func uninstall() : async CommonModel.BoolResult {
        let launchpad = await LaunchpadUtil.getLaunchpadDetail(launchpadDetail);
        if (msg.caller == launchpad.creatorPrincipal) {
            launchpadCanisters.clear();
            launchpadCanisterEntries := [];
            for (cid in routeCanisterMap.keys()) {
                routeCanisterMap.delete(cid);
            };
            launchpadDetail := null;
            uniqueTicket := "";
            whitelist := [];
            installed := false;
            return #ok(not installed);
        };
        return #err("Denied!!");
    };

    // Get all of launchpad canister directly
    public query func getLaunchpadCanisters() : async [Launchpad.LaunchpadCanister] {
        return launchpadCanisters.toArray();
    };

    public query func getCanisters() : async CommonModel.ResponseResult<[CanisterModel.CanisterView]> {
        return #ok(canisters.toArray());
    };

    private func _setController(canister : Principal, controller : Principal, caller : Principal) : async () {
        await ic00.update_settings({
            canister_id = canister;
            settings = {
                controllers = [
                    caller,
                    controller,
                    Principal.fromActor(this),
                ];
            };
        });
    };

    public shared (msg) func setController(canisterId : Text, controller : Text) : async Bool {
        let launchpad = await LaunchpadUtil.getLaunchpadDetail(launchpadDetail);
        if (msg.caller == launchpad.creatorPrincipal) {
            let canisterPrincipal = Principal.fromText(canisterId);
            let controllerPrincipal = Principal.fromText(controller);

            await _setController(canisterPrincipal, controllerPrincipal, msg.caller);

            return true;
        };
        return false;
    };

    public query func cycleBalance() : async CommonModel.NatResult {
        // FIXME 0 assert msg.caller == owner;
        return #ok(ExperimentalCycles.balance());
    };
    public shared (msg) func cycleAvailable() : async CommonModel.NatResult {
        // FIXME 0 assert msg.caller == owner;
        return #ok(ExperimentalCycles.available());
    };

    system func preupgrade() {
        canisterArry := canisters.toArray();
        launchpadCanisterArry := launchpadCanisters.toArray();
        launchpadCanisterEntries := Iter.toArray(routeCanisterMap.entries());
        ticketEntries := Iter.toArray(ticketMap.entries());
    };

    system func postupgrade() {
        for (item in canisterArry.vals()) {
            canisters.add(item);
        };
        canisterArry := [];
        for (item in launchpadCanisterArry.vals()) {
            launchpadCanisters.add(item);
        };
        launchpadCanisterArry := [];
        launchpadCanisterEntries := [];
        ticketEntries := [];
    };
};
