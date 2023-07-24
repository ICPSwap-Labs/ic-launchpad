import Nat "mo:base/Nat";
import Text "mo:base/Text";
import Bool "mo:base/Bool";
import Blob "mo:base/Blob";
import Time "mo:base/Time";
import Debug "mo:base/Debug";
import Error "mo:base/Error";
import Array "mo:base/Array";
import Order "mo:base/Order";
import Buffer "mo:base/Buffer";
import Option "mo:base/Option";
import Principal "mo:base/Principal";
import ExperimentalCycles "mo:base/ExperimentalCycles";

import TextUtil "mo:commons/TextUtils";
import ListUtil "mo:commons/CollectUtils";
import PrincipalUtil "mo:commons/PrincipalUtils";

import Launchpad "./Launchpad";
import CommonModel "./commons/CommonModel";
import CanisterModel "./commons/CanisterModel";
import TokenFactory "./token/TokenFactory";
import LaunchpadUtil "./commons/LaunchpadUtil";
import LaunchpadManager "./LaunchpadManager";

actor LaunchpadController {

    private let _initCycles : Nat = 1860000000000;
    private stable var installed : Bool = false;
    private stable var canisterArry : [CanisterModel.CanisterView] = [];
    private let canisters : Buffer.Buffer<CanisterModel.CanisterView> = Buffer.Buffer<CanisterModel.CanisterView>(0);
    private stable var launchpadArry : [Launchpad.Property] = [];
    private let launchpads : Buffer.Buffer<Launchpad.Property> = Buffer.Buffer<Launchpad.Property>(0);

    private stable var whitelist : [Text] = ["1d91ee3f04c8a548178441792b1a2d80a93c6fa2ec90b6620a0c23637b7ce0ac"];

    private let ic00 = actor "aaaaa-aa" : actor {
        update_settings : {
            canister_id : Principal;
            settings : { controllers : [Principal] };
        } -> async ();
    };

    /**
   * Launchpad owner call this method to generate the Launchpad.
   * It will generate a empty(un-installed) Launchpad Manager.
   */
    public shared (msg) func generate(prop : Launchpad.Property) : async CommonModel.ResponseResult<Text> {
        if (not isInWhitelist(msg.caller)) {
            throw Error.reject("You_are_not_in_whitelist");
        };

        let wrappedProp = {
            id = prop.id;
            cid = prop.cid;
            name = prop.name;
            description = prop.description;
            startDateTime = prop.startDateTime;
            endDateTime = prop.endDateTime;
            depositDateTime = prop.depositDateTime;
            withdrawalDateTime = prop.withdrawalDateTime;
            soldTokenId = prop.soldTokenId;
            soldTokenStandard = prop.soldTokenStandard;
            pricingTokenId = prop.pricingTokenId;
            pricingTokenStandard = prop.pricingTokenStandard;
            initialExchangeRatio = prop.initialExchangeRatio;
            soldQuantity = prop.soldQuantity;
            expectedSellQuantity = prop.expectedSellQuantity;
            extraTokenFee = ?(await LaunchpadUtil.getExtraQuntity(prop.soldTokenId, prop.soldTokenStandard));
            depositedQuantity = prop.depositedQuantity;
            fundraisingPricingTokenQuantity = prop.fundraisingPricingTokenQuantity;
            expectedFundraisingPricingTokenQuantity = prop.expectedFundraisingPricingTokenQuantity;
            limitedAmountOnce = prop.limitedAmountOnce;
            receiveTokenDateTime = prop.receiveTokenDateTime;
            creator = prop.creator;
            creatorPrincipal = prop.creatorPrincipal;
            createdDateTime = prop.createdDateTime;
            settled = false;
            canisterQuantity = prop.canisterQuantity;
        };

        if (await canCreate(msg.caller, wrappedProp.name, wrappedProp.soldTokenId, wrappedProp.soldTokenStandard, TextUtil.toNat(wrappedProp.expectedSellQuantity), Option.get<Nat>(wrappedProp.extraTokenFee, 0))) {
            let cycles = Nat.mul(prop.canisterQuantity + 1, _initCycles);

            ExperimentalCycles.add(cycles); // pay for the cycle fee
            let manager : Launchpad.LaunchpadManager = await LaunchpadManager.LaunchpadManager();
            let cid : Text = PrincipalUtil.toText(Principal.fromActor(manager));
            let canisterView : CanisterModel.CanisterView = {
                id = cid;
                name = "LaunchpadManager(" # wrappedProp.name # ")";
                cycle = 0;
            };
            canisters.add(canisterView);
            await _setController(
                Principal.fromActor(manager),
                Principal.fromText(LaunchpadUtil.WALLET_CANISTER_ID),
                msg.caller,
            );
            installed := true;
            Debug.print("Generate manager canister(" # cid # ") success");
            return #ok(cid);
        };
        return #ok("");
    };

    /**
   * Installing Launchpad Manager and generating several Launchpad Canister.
   */
    public shared (msg) func install(cid : Text, prop : Launchpad.Property, wl : [Text]) : async CommonModel.ResponseResult<Launchpad.Property> {
        if (not isInWhitelist(msg.caller)) {
            throw Error.reject("You_are_not_in_whitelist");
        };
        let wrappedProp : Launchpad.Property = {
            id = prop.id;
            cid = prop.cid;
            name = prop.name;
            description = prop.description;
            startDateTime = prop.startDateTime;
            endDateTime = prop.endDateTime;
            depositDateTime = prop.depositDateTime;
            withdrawalDateTime = prop.withdrawalDateTime;
            soldTokenId = prop.soldTokenId;
            soldTokenStandard = prop.soldTokenStandard;
            pricingTokenId = prop.pricingTokenId;
            pricingTokenStandard = prop.pricingTokenStandard;
            initialExchangeRatio = prop.initialExchangeRatio;
            soldQuantity = prop.soldQuantity;
            expectedSellQuantity = prop.expectedSellQuantity;
            extraTokenFee = ?(await LaunchpadUtil.getExtraQuntity(prop.soldTokenId, prop.soldTokenStandard));
            depositedQuantity = prop.depositedQuantity;
            fundraisingPricingTokenQuantity = prop.fundraisingPricingTokenQuantity;
            expectedFundraisingPricingTokenQuantity = prop.expectedFundraisingPricingTokenQuantity;
            limitedAmountOnce = prop.limitedAmountOnce;
            receiveTokenDateTime = prop.receiveTokenDateTime;
            creator = prop.creator;
            creatorPrincipal = prop.creatorPrincipal;
            createdDateTime = prop.createdDateTime;
            settled = ?false;
            canisterQuantity = prop.canisterQuantity;
        };
        let manager : Launchpad.LaunchpadManager = actor (cid) : Launchpad.LaunchpadManager;
        switch (await manager.install(msg.caller, wrappedProp, wl)) {
            case (#ok(success)) {
                let launchpad : Launchpad.Property = switch (await manager.getDetail()) {
                    case (#ok(detail)) { detail };
                    case (#err(code)) { throw Error.reject(code) };
                };
                launchpads.add(launchpad);
                Debug.print("Install manager canister(" # cid # ") success");
                return #ok(launchpad);
            };
            case (#err(code)) {
                throw Error.reject("launchpad_manager_canister_init_failed: " # code);
            };
        };
    };

    public shared (msg) func uninstall() : async CommonModel.BoolResult {
        if (not isInWhitelist(msg.caller)) {
            throw Error.reject("You_are_not_in_whitelist");
        };
        canisters.clear();
        launchpads.clear();
        installed := false;
        return #ok(not installed);
    };

    // checking if the owner can create Launchpad
    private func canCreate(owner : Principal, name : Text, soldTokenId : Text, soldTokenStandard : Text, expectedSellQuantity : Nat, extraTokenFee : Nat) : async Bool {
        switch (Array.find<Launchpad.Property>(launchpads.toArray(), func(l : Launchpad.Property) : Bool { return Text.equal(l.name, name) })) {
            case null {
                let creator : Text = PrincipalUtil.toAddress(owner);
                let tokenAdapter = TokenFactory.getAdapter(soldTokenId, soldTokenStandard);
                var tokenBalance : Nat = await LaunchpadUtil.getBalance(owner, soldTokenId, soldTokenStandard);
                if (tokenBalance < expectedSellQuantity + extraTokenFee) {
                    // out of token balance, expectedSellQuantity + trans fee
                    throw Error.reject("insufficient_token_balance");
                    return false;
                };
                return true;
            };
            case (?l) {
                throw Error.reject("duplicated_launchpad_name");
                return false;
            };
        };
        return false;
    };

    // For all of users(include anonymous users)
    public query func getAllPools(status : Text, offset : Nat, limit : Nat) : async CommonModel.ResponseResult<CommonModel.Page<Launchpad.Property>> {
        var pool : Buffer.Buffer<Launchpad.Property> = Buffer.Buffer<Launchpad.Property>(0);
        let now : Time.Time = Time.now();
        for (launchpad in launchpads.vals()) {
            if (Text.equal(status, "all")) {
                pool.add(launchpad);
            } else if (
                Text.equal(status, "processing") and now < launchpad.endDateTime
            ) {
                pool.add(launchpad);
            } else if (
                Text.equal(status, "finished") and now >= launchpad.endDateTime
            ) {
                pool.add(launchpad);
            };
        };
        var poolArry : [Launchpad.Property] = pool.toArray();
        if (Text.equal(status, "processing")) {
            poolArry := Array.sort(
                poolArry,
                func(a : Launchpad.Property, b : Launchpad.Property) : Order.Order {
                    if (a.startDateTime > b.startDateTime) {
                        return #greater;
                    } else if (a.startDateTime == b.startDateTime) {
                        return #equal;
                    } else {
                        return #less;
                    };
                },
            );
        } else if (Text.equal(status, "finished")) {
            poolArry := Array.sort(
                poolArry,
                func(a : Launchpad.Property, b : Launchpad.Property) : Order.Order {
                    if (a.endDateTime < b.endDateTime) {
                        return #greater;
                    } else if (a.endDateTime == b.endDateTime) {
                        return #equal;
                    } else {
                        return #less;
                    };
                },
            );
        };
        let result : [Launchpad.Property] = ListUtil.arrayRange<Launchpad.Property>(poolArry, offset, limit);
        return #ok({
            totalElements = pool.size();
            content = result;
            offset = offset;
            limit = limit;
        });
    };

    // Get pool of owner-self. This owner can generate lots of launchpad
    public query (msg) func getPoolsByOwner(ownerAddress : Text, offset : Nat, limit : Nat) : async CommonModel.ResponseResult<CommonModel.Page<Launchpad.Property>> {
        var pool : Buffer.Buffer<Launchpad.Property> = Buffer.Buffer<Launchpad.Property>(0);
        for (launchpad in launchpads.vals()) {
            if (launchpad.creator == ownerAddress) {
                pool.add(launchpad);
            };
        };
        let result : [Launchpad.Property] = ListUtil.arrayRange<Launchpad.Property>(
            Array.sort(
                pool.toArray(),
                func(a : Launchpad.Property, b : Launchpad.Property) : Order.Order {
                    if (a.createdDateTime > b.createdDateTime) {
                        return #greater;
                    } else if (a.createdDateTime == b.createdDateTime) {
                        return #equal;
                    } else {
                        return #less;
                    };
                },
            ),
            offset,
            limit,
        );
        return #ok({
            totalElements = pool.size();
            content = result;
            offset = offset;
            limit = limit;
        });
    };

    public query func getCanisters() : async CommonModel.ResponseResult<[CanisterModel.CanisterView]> {
        return #ok(canisters.toArray());
    };

    public shared(msg) func archive() : async CommonModel.BoolResult {
        if (not isInWhitelist(msg.caller)) {
            throw Error.reject("You_are_not_in_whitelist");
        };

        for (launchpad in launchpads.vals()) {
            let managerCanister : Launchpad.LaunchpadManager = actor (launchpad.cid) : Launchpad.LaunchpadManager;
            await managerCanister.archive();
        };
        return #ok(true);
    };

    public shared(msg) func result() : async Text {
        if (not isInWhitelist(msg.caller)) {
            throw Error.reject("You_are_not_in_whitelist");
        };
        var record : Text = "============================= Archive Start  =============================";
        Debug.print(record);
        for (launchpad in launchpads.vals()) {
            let managerCanister : Launchpad.LaunchpadManager = actor (launchpad.cid) : Launchpad.LaunchpadManager;
            let m : Text = "[Archive result] Manager canister(" # launchpad.cid # ")";
            record := record # "\n" # m;
            Debug.print(m);
            let launchpadCanisters : [Launchpad.LaunchpadCanister] = await managerCanister.getLaunchpadCanisters();
            if (launchpadCanisters.size() > 0) {
                for (launchpadCanister in launchpadCanisters.vals()) {
                    let n : Text = "[Archive result] Manager canister(" # launchpad.cid # ") -> Launchpad canister(" # PrincipalUtil.toText(Principal.fromActor(launchpadCanister)) # ")";
                    record := record # "\n" # n;
                    Debug.print(n);
                };
            } else {
                let n : Text = "[Archive result] Manager canister(" # launchpad.cid # ") -> no more Launchpad canister";
                record := record # "\n" # n;
                Debug.print(n);
            };
        };
        let e : Text = "============================= Archive End  =============================";
        record := record # "\n" # e;
        Debug.print(e);
        return record;
    };

    /*============================================ whitelist for owner start  ============================================*/
    private func isAdmin(caller : Text) : Bool {
        return ListUtil.arrayContains<Text>(LaunchpadUtil.ADMIN_LIST, caller, Text.equal);
    };

    // This whitelist is used for checking owners who can if genreate Launchpad or not.
    private func isInWhitelist(caller : Principal) : Bool {
        return ListUtil.arrayContains<Text>(whitelist, PrincipalUtil.toAddress(caller), Text.equal);
    };

    public shared (msg) func addWhitelist(accounts : [Text]) : async Bool {
        assert (isAdmin(PrincipalUtil.toAddress(msg.caller)));
        for (account in accounts.vals()) {
            if (not ListUtil.arrayContains<Text>(whitelist, account, Text.equal)) {
                whitelist := Array.append<Text>(whitelist, [account]);
            };
        };
        return true;
    };

    public shared (msg) func deleteWhitelist(accounts : [Text]) : async Bool {
        assert (isAdmin(PrincipalUtil.toAddress(msg.caller)));
        for (account in accounts.vals()) {
            if (ListUtil.arrayContains<Text>(whitelist, account, Text.equal)) {
                whitelist := ListUtil.arrayRemove<Text>(whitelist, account, Text.equal);
            };
        };
        return true;
    };

    public query (msg) func getWhitelist() : async [Text] {
        assert (isAdmin(PrincipalUtil.toAddress(msg.caller)));
        return whitelist;
    };
    /*============================================ whitelist for owner end  ============================================*/

    // public func setPricingTokenCanisterId(pricingTokenCid: Text) : async () {
    //   LaunchpadUtil.PricingToken_CANISTER_ID := pricingTokenCid;
    // }

    public query func cycleBalance() : async CommonModel.NatResult {
        // FIXME 0 assert msg.caller == owner;
        return #ok(ExperimentalCycles.balance());
    };
    public shared (msg) func cycleAvailable() : async CommonModel.NatResult {
        // FIXME 0 assert msg.caller == owner;
        return #ok(ExperimentalCycles.available());
    };

    private func _setController(canister : Principal, controller : Principal, caller : Principal) : async () {
        await ic00.update_settings({
            canister_id = canister;
            settings = {
                controllers = [
                    caller,
                    controller,
                    Principal.fromActor(LaunchpadController),
                ];
            };
        });
    };

    public shared (msg) func setController(canisterId : Text, controller : Text) : async Bool {
        assert (isAdmin(PrincipalUtil.toAddress(msg.caller)));

        let canisterPrincipal = Principal.fromText(canisterId);
        let controllerPrincipal = Principal.fromText(controller);

        await _setController(canisterPrincipal, controllerPrincipal, msg.caller);

        return true;
    };

    system func preupgrade() {
        canisterArry := canisters.toArray();
        launchpadArry := launchpads.toArray();
    };

    system func postupgrade() {
        for (item in canisterArry.vals()) {
            canisters.add(item);
        };
        canisterArry := [];
        for (item in launchpadArry.vals()) {
            launchpads.add(item);
        };
        launchpadArry := [];
    };
};
