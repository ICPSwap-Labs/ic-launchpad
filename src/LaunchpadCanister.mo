import Text "mo:base/Text";
import Nat "mo:base/Nat";
import Nat64 "mo:base/Nat64";
import Int "mo:base/Int";
import Bool "mo:base/Bool";
import Time "mo:base/Time";
import Error "mo:base/Error";
import Debug "mo:base/Debug";
import Buffer "mo:base/Buffer";
import Option "mo:base/Option";
import Principal "mo:base/Principal";
import CommonModel "mo:commons/model/CommonModel";
import ExperimentalCycles "mo:base/ExperimentalCycles";
import TextUtil "mo:commons/utils/TextUtils";
import IntUtil "mo:commons/utils/IntUtils";
import ListUtil "mo:commons/utils/ListUtils";
import PrincipalUtil "mo:commons/utils/PrincipalUtils";
import LaunchpadStorage "canister:LaunchpadStorage";
import TokenFactory "./token/TokenFactory";

import LaunchpadUtil "./LaunchpadUtil";
import Launchpad "./Launchpad";

actor class LaunchpadCanister() : async Launchpad.LaunchpadCanister = this {

  public type TokenMetadata = {
    var name : Text;
    var symbol : Text;
    var decimals : Nat;
    var metadata : ?Blob;
    var ownerAccount : Text;
  };

  private let deafultMetadata : TokenMetadata = {
    var name = "";
    var symbol = "";
    var decimals = 0;
    var metadata = null;
    var ownerAccount = "";
  };

  private stable var managerAddress : Text = "";
  private stable var installed : Bool = false;
  private stable var launchpadDetail : ?Launchpad.Property = null;
  private let investorAddresses : Buffer.Buffer<Text> = Buffer.Buffer<Text>(0);
  private stable var investorAddressArry : [Text] = [];
  private stable var investorArry : [Launchpad.Investor] = [];
  private stable var owner : ?Principal = null;
  private stable var whitelist : [Text] = [];
  private var tokenMetadata : TokenMetadata = deafultMetadata;
  private var pricingTokenMetadata : TokenMetadata = deafultMetadata;
  private let investors : Buffer.Buffer<Launchpad.Investor> = Buffer.Buffer<Launchpad.Investor>(0);

  public shared (msg) func install(prop : Launchpad.Property, _managerAddress : Text, _whitelist : [Text]) : async CommonModel.BoolResult {
    if (installed) {
      return #err("already_been_installed");
    };
    managerAddress := _managerAddress;
    whitelist := _whitelist;
    owner := ?msg.caller;
    launchpadDetail := ?prop;
    installed := true;
    return #ok(installed);
  };

  public shared (msg) func addInvestorAddress(investorAddress : Text) : async () {
    if (msg.caller == Option.get<Principal>(owner, Principal.fromActor(this))) {
      investorAddresses.add(investorAddress);
    } else {
      throw Error.reject("Denied!!");
    };
  };

  private func isValidInvestor(investorAddress : Text) : Bool {
    return ListUtil.arrayContains<Text>(investorAddresses.toArray(), investorAddress, Text.equal);
  };

  private func isInWhitelist(userAddress : Text) : Bool {
    if (whitelist.size() == 0) {
      return true;
    };
    return ListUtil.arrayContains<Text>(whitelist, userAddress, Text.equal);
  };

  // add new investor --pricingToken--> Launchpad Canister
  public shared (msg) func addInvestor(expectedDepositedPricingTokenQuantity : Text) : async CommonModel.BoolResult {
    let investorSelfCaller : Principal = msg.caller;
    let investorAddress : Text = PrincipalUtil.toAddress(investorSelfCaller);
    if (isValidInvestor(investorAddress)) {
      if (isInWhitelist(investorAddress)) {
        let launchpad : Launchpad.Property = await LaunchpadUtil.getLaunchpadDetail(launchpadDetail);
        // investors can participate the launchpad in the range of specified date
        let now : Time.Time = Time.now();
        if (launchpad.startDateTime <= now and now < launchpad.endDateTime) {
          let depositedPricingTokenQuantity : Nat = await transferPricingTokenFromInvestorToCanister(investorSelfCaller, TextUtil.toNat(expectedDepositedPricingTokenQuantity));
          let newInvestor : Launchpad.Investor = {
            id = investorAddress;
            principal = investorSelfCaller;
            participatedDateTime = now;
            expectedDepositedPricingTokenQuantity = TextUtil.fromNat(depositedPricingTokenQuantity);
            expectedBuyTokenQuantity = TextUtil.fromNat(await LaunchpadUtil.getTokenQuantityByPricingTokenQuantity(depositedPricingTokenQuantity, TextUtil.toNat(launchpad.initialExchangeRatio), launchpad.soldTokenId, launchpad.soldTokenStandard, launchpad.pricingTokenId, launchpad.pricingTokenStandard));
            finalTokenSet = null;
            withdrawalDateTime = null;
          };
          investors.add(newInvestor);
          let tokenAdapter = TokenFactory.getAdapter(launchpad.pricingTokenId, launchpad.pricingTokenStandard);
          var metadata : [(Text, Value)] = [];
          try {
            metadata := await tokenAdapter.metadata();
          } catch (e) {
            throw Error.reject("get metadata failed: " # Error.message(e));
          };
          let pricingTokenName = getName(metadata);
          let pricingTokenSymbol = getSymbol(metadata);

          await LaunchpadStorage.addTransaction(
            managerAddress,
            {
              managerAddress = managerAddress;
              launchpadAddress = launchpad.id;
              time = newInvestor.participatedDateTime;
              operationType = "deposit";
              tokenName = pricingTokenName;
              tokenSymbol = pricingTokenSymbol;
              quantity = newInvestor.expectedDepositedPricingTokenQuantity;
              address = newInvestor.id;
            },
          );
          return #ok(true);
        } else {
          return #err("The_available_time_is_out_of_range_when_add_investor");
        };
      } else {
        return #err("Out_of_the_whitelist");
      };
    } else {
      return #err("Denied!!");
    };
  };

  // investor --pricingToken--> Launchpad Canister
  private func transferPricingTokenFromInvestorToCanister(investorPrincipal : Principal, pricingTokenQuantity : Nat) : async Nat {
    let canisterAddress : Text = LaunchpadUtil.getCanisterAddress(this);
    let investorAddress : Text = PrincipalUtil.toAddress(investorPrincipal);
    let launchpad : Launchpad.Property = await LaunchpadUtil.getLaunchpadDetail(launchpadDetail);
    let tokenAdapter = TokenFactory.getAdapter(launchpad.pricingTokenId, launchpad.pricingTokenStandard);
    var transFee : Nat = 0;
    try {
      let transFee : Nat = await tokenAdapter.fee();
    } catch (e) {
      throw Error.reject(Error.message(e));
    };
    if (pricingTokenQuantity > transFee) {
      var params = {
        from = { owner = investorPrincipal; subaccount = null };
        from_subaccount = null;
        to = {
          owner = LaunchpadUtil.getCanisterPrincipal(this);
          subaccount = null;
        };
        fee = null;
        amount = pricingTokenQuantity;
        memo = null;
        created_at_time = null;
      };
      switch (await tokenAdapter.transferFrom(params)) {
        case (#Ok(index)) {
          Debug.print("transfer from \"" # investorAddress # "\" to \"" # canisterAddress # "\", amount: " # debug_show (pricingTokenQuantity) # ", token: PricingToken, amountPrefee: " # TextUtil.fromNat(pricingTokenQuantity -transFee));
          return pricingTokenQuantity -transFee;
        };
        case (#Err(code)) {
          let description : Text = "{transaction: {from: \"" # investorAddress # "\", to: \"" # canisterAddress # "\", value: " # TextUtil.fromNat(pricingTokenQuantity) # ", token: \"PricingToken\", description: \"investor --pricingToken--> Launchpad Canister(" # canisterAddress # ")\"}}";
          throw Error.reject("tarsnfer_from_investor(" # investorAddress # ")_2_canister_failed: " # debug_show (code) # ", " # description);
        };
      };
    } else {
      throw Error.reject("Your_token(" # TextUtil.fromNat(pricingTokenQuantity) # ")_is_lower_than_trans_fee(" # TextUtil.fromNat(transFee) # ")");
    };
  };

  // canister --token--> investor
  private func transferTokenFromCanisterToInvestor(investor : Launchpad.Investor, tokenQuantity : Nat, tokenCid : Text, tokenStandard : Text) : async Bool {
    let canisterAddress : Text = LaunchpadUtil.getCanisterAddress(this);
    let canisterPrincipal : Principal = LaunchpadUtil.getCanisterPrincipal(this);
    let tokenAdapter = TokenFactory.getAdapter(tokenCid, tokenStandard);
    let transFee : Nat = await LaunchpadUtil.getFee(tokenCid, tokenStandard);
    Debug.print("Starting transfer, tokenQuantity: " # debug_show (tokenQuantity) # ", transFee" # debug_show (transFee));
    if (tokenQuantity > 0) {
      let description : Text = "{transaction: {from: \"" # canisterAddress # "\", to: \"" # investor.id # "\", value: " # TextUtil.fromNat(tokenQuantity - transFee) # ", token: \"" # tokenCid # "\", description: \"launchpad canister --token--> investor\"}}";
      Debug.print("Starting " # description);
      var params = {
        from = { owner = canisterPrincipal; subaccount = null };
        from_subaccount = null;
        to = { owner = investor.principal; subaccount = null };
        fee = null;
        amount = tokenQuantity;
        memo = null;
        created_at_time = null;
      };
      return switch (await tokenAdapter.transfer(params)) {
        case (#Ok(index)) { return true };
        case (#Err(code)) {
          throw Error.reject("tarsnfer_from_canister(" # canisterAddress # ")_to_investor(" # investor.id # ")_failed: " # debug_show (code) # ", " # description);
        };
      };
    } else {
      throw Error.reject("Your_token(" # TextUtil.fromNat(tokenQuantity) # ")_is_lower_than_trans_fee(" # TextUtil.fromNat(transFee) # ")");
    };
    return false;
  };

  public shared (msg) func transferByAddress(fromPrincipal : Principal, destinationPrincipal : Principal, tokenQuantity : Nat, tokenCid : Text, tokenStandard : Text) : async Bool {
    if (msg.caller == Option.get<Principal>(owner, Principal.fromActor(this))) {
      let tokenAdapter = TokenFactory.getAdapter(tokenCid, tokenStandard);
      let transFee : Nat = await LaunchpadUtil.getFee(tokenCid, tokenStandard);
      let fromAddress : Text = PrincipalUtil.toAddress(fromPrincipal);
      let destinationAddress : Text = PrincipalUtil.toAddress(destinationPrincipal);
      if (tokenQuantity > transFee) {
        var params = {
          from = { owner = fromPrincipal; subaccount = null };
          from_subaccount = null;
          to = { owner = destinationPrincipal; subaccount = null };
          fee = null;
          amount = tokenQuantity;
          memo = null;
          created_at_time = null;
        };
        switch (await tokenAdapter.transfer(params)) {
          case (#Ok(index)) {
            let description : Text = "{transaction: {from: \"" # fromAddress # "\", to: \"" # destinationAddress # "\", value: " # TextUtil.fromNat(tokenQuantity) # ", token: \"" # tokenCid # "\"}}";
            Debug.print("Transfer success: " # description);
            return true;
          };
          case (#Err(code)) {
            let description : Text = "{transaction: {from: \"" # fromAddress # "\", to: \"" # destinationAddress # "\", value: " # TextUtil.fromNat(tokenQuantity) # ", token: \"" # tokenCid # "\"}}";
            throw Error.reject("tarsnfer_from_canister(" # fromAddress # ")_to_investor(" # destinationAddress # ")_failed: " # debug_show (code) # ", " # description);
          };
        };
      } else {
        throw Error.reject("Your_token(" # TextUtil.fromNat(tokenQuantity) # ")_is_lower_than_trans_fee(" # TextUtil.fromNat(transFee) # ")");
      };
    };
    return false;
  };

  // find investor and the index of the investor
  private func findInvestorByAddress(callerAddress : Text) : Launchpad.InvestorUnit {
    var index : Int = 0;
    for (investor in investors.vals()) {
      if (investor.id == callerAddress) {
        return {
          investor = investor;
          index = index;
        };
      };
      index += 1;
    };
    return {
      investor = {
        id = "";
        principal = LaunchpadUtil.getCanisterPrincipal(this);
        participatedDateTime = 0;
        expectedBuyTokenQuantity = "";
        expectedDepositedPricingTokenQuantity = "";
        finalTokenSet = null;
        withdrawalDateTime = null;
      };
      index = -1;
    };
  };

  // append investor --pricingToken--> Launchpad Canister
  public shared (msg) func appendPricingTokenQuantity(pricingTokenQuantity : Text) : async CommonModel.BoolResult {
    let investorPrincipal : Principal = msg.caller;
    let investorAddress : Text = PrincipalUtil.toAddress(investorPrincipal);
    if (isValidInvestor(investorAddress)) {
      if (isInWhitelist(investorAddress)) {
        let now : Time.Time = Time.now();
        let launchpad : Launchpad.Property = await LaunchpadUtil.getLaunchpadDetail(launchpadDetail);
        if (launchpad.startDateTime <= now and now < launchpad.endDateTime) {
          let unit : Launchpad.InvestorUnit = findInvestorByAddress(investorAddress);
          let investor : Launchpad.Investor = unit.investor;
          let appendDepositedPricingTokenQuantity : Nat = await transferPricingTokenFromInvestorToCanister(investorPrincipal, TextUtil.toNat(pricingTokenQuantity));
          let expectedDepositedPricingTokenQuantity : Nat = TextUtil.toNat(investor.expectedDepositedPricingTokenQuantity) + appendDepositedPricingTokenQuantity;
          investors.put(
            IntUtil.toNat(unit.index),
            {
              id = investor.id;
              principal = investor.principal;
              participatedDateTime = investor.participatedDateTime;
              expectedDepositedPricingTokenQuantity = TextUtil.fromNat(expectedDepositedPricingTokenQuantity);
              expectedBuyTokenQuantity = TextUtil.fromNat(await LaunchpadUtil.getTokenQuantityByPricingTokenQuantity(expectedDepositedPricingTokenQuantity, TextUtil.toNat(launchpad.initialExchangeRatio), launchpad.soldTokenId, launchpad.soldTokenStandard, launchpad.pricingTokenId, launchpad.pricingTokenStandard));
              finalTokenSet = null;
              withdrawalDateTime = null;
            },
          );
          let tokenAdapter = TokenFactory.getAdapter(launchpad.pricingTokenId, launchpad.pricingTokenStandard);
          var pricingTokenName : Text = "";
          var pricingTokenSymbol : Text = "";
          try {
            let pricingTokenMeta = await tokenAdapter.metadata();
            pricingTokenName := getName(pricingTokenMeta);
            pricingTokenSymbol := getSymbol(pricingTokenMeta);
          } catch (e) {
            throw Error.reject("get metadata failed: " #debug_show (Error.message(e)));
          };
          await LaunchpadStorage.addTransaction(
            managerAddress,
            {
              managerAddress = managerAddress;
              launchpadAddress = launchpad.id;
              time = now;
              operationType = "deposit";
              tokenName = pricingTokenName;
              tokenSymbol = pricingTokenSymbol;
              quantity = pricingTokenQuantity;
              address = investor.id;
            },
          );
          return #ok(true);
        } else {
          return #err("The_available_time_is_out_of_range_when_append_pricingToken_from_investor");
        };
      } else {
        return #err("Out_of_the_whitelist");
      };
    } else {
      return #err("Denied!!");
    };
  };

  public type Value = { #Nat : Nat; #Int : Int; #Blob : Blob; #Text : Text };
  private func getSymbol(metadata : [(Text, Value)]) : Text {
    var tokenSymbol = "";
    for ((key, value) in metadata.vals()) {
      if (key == "symbol") {
        tokenSymbol := switch (value) {
          case (#Text(symbol)) {
            symbol;
          };
          case (_) {
            "error";
          };
        };
      };
    };
    return tokenSymbol;
  };
  private func getName(metadata : [(Text, Value)]) : Text {
    var tokenName = "";
    for ((key, value) in metadata.vals()) {
      if (key == "name") {
        tokenName := switch (value) {
          case (#Text(name)) {
            name;
          };
          case (_) {
            "error";
          };
        };
      };
    };
    return tokenName;
  };
  private func getDecimals(metadata : [(Text, Value)]) : Nat {
    var tokenDecimal = 0;
    for ((key, value) in metadata.vals()) {
      if (key == "decimals") {
        tokenDecimal := switch (value) {
          case (#Nat(decimals)) {
            decimals;
          };
          case (_) {
            0;
          };
        };
      };
    };
    return tokenDecimal;
  };

  public query func getInvestorsSize() : async Nat {
    return investors.size();
  };

  public query func getInvestors() : async [Launchpad.Investor] {
    return investors.toArray();
  };

  // only self can call this function
  // This function should be called after the launchpad settled.
  public shared (msg) func withdraw2Investor() : async CommonModel.ResponseResult<Launchpad.TokenSet> {
    if (isValidInvestor(PrincipalUtil.toAddress(msg.caller))) {
      let launchpad : Launchpad.Property = await LaunchpadUtil.getLaunchpadDetail(launchpadDetail);
      let now : Time.Time = Time.now();
      if (launchpad.endDateTime < now) {
        // The investor only can withdraw after the launchpad ended
        let investorUnit : Launchpad.InvestorUnit = findInvestorByAddress(PrincipalUtil.toAddress(msg.caller));
        let investor : Launchpad.Investor = investorUnit.investor;
        switch (investor.withdrawalDateTime) {
          case (?withdrawalDateTime) {
            return #err("has_withdrawn_already");
          };
          case (_) {
            switch (investor.finalTokenSet) {
              case (?tokenSet) {
                Debug.print("canister -token-> investor");
                Debug.print("token: " # tokenSet.token.quantity);
                // canister -token-> investor
                if (await transferTokenFromCanisterToInvestor(investor, TextUtil.toNat(tokenSet.token.quantity), launchpad.soldTokenId, launchpad.soldTokenStandard)) {
                  await LaunchpadStorage.addTransaction(
                    managerAddress,
                    {
                      managerAddress = managerAddress;
                      launchpadAddress = launchpad.id;
                      time = now;
                      operationType = "withdraw";
                      tokenName = tokenSet.token.name;
                      tokenSymbol = tokenSet.token.symbol;
                      quantity = tokenSet.token.quantity;
                      address = investor.id;
                    },
                  );
                  let restOfPricingTokenQuantity : Nat = TextUtil.toNat(tokenSet.pricingToken.quantity);
                  if (restOfPricingTokenQuantity > 0) {
                    // has the rest of PricingToken
                    Debug.print("canister -pricingToken-> investor");
                    Debug.print("the rest of pricingToken: " # debug_show (restOfPricingTokenQuantity));
                    if (await transferTokenFromCanisterToInvestor(investor, restOfPricingTokenQuantity, launchpad.pricingTokenId, launchpad.pricingTokenStandard)) {
                      await LaunchpadStorage.addTransaction(
                        managerAddress,
                        {
                          managerAddress = managerAddress;
                          launchpadAddress = launchpad.id;
                          time = now;
                          operationType = "withdraw";
                          tokenName = tokenSet.pricingToken.name;
                          tokenSymbol = tokenSet.pricingToken.symbol;
                          quantity = tokenSet.pricingToken.quantity;
                          address = investor.id;
                        },
                      );
                    };
                  };
                };
                investors.put(
                  IntUtil.toNat(investorUnit.index),
                  {
                    id = investor.id;
                    principal = investor.principal;
                    participatedDateTime = investor.participatedDateTime;
                    expectedDepositedPricingTokenQuantity = investor.expectedDepositedPricingTokenQuantity;
                    expectedBuyTokenQuantity = investor.expectedBuyTokenQuantity;
                    finalTokenSet = ?tokenSet;
                    withdrawalDateTime = ?now;
                  },
                );
                return #ok(tokenSet);
              };
              case (_) {
                return #err("withdraw_to_investor_failed_owner_has_not_settled");
              };
            };
          };
        };
      };
      return #err("withdraw_to_investor_failed_time_does_not_up");
    } else {
      return #err("Denied!!");
    };
  };

  // only self can call this function
  public query func getInvestorDetail(callerAddress : Text) : async CommonModel.ResponseResult<Launchpad.Investor> {
    return #ok(findInvestorByAddress(callerAddress).investor);
  };

  // The total quantity of expected deposit PricingToken
  public query func getPricingTokenQuantity() : async CommonModel.ResponseResult<Nat> {
    var expectedBuyPricingTokenQuantity : Nat = 0;
    for (investor in investors.vals()) {
      expectedBuyPricingTokenQuantity += TextUtil.toNat(investor.expectedDepositedPricingTokenQuantity);
    };
    return #ok(expectedBuyPricingTokenQuantity);
  };

  // Compute final token quantity of investors
  public shared (msg) func computeFinalTokenViewSet(expectedSellQuantity : Nat, fundraisingTotalTokenQuantity : Nat) : async Launchpad.TokenViewSet {
    if (msg.caller == Option.get<Principal>(owner, Principal.fromActor(this))) {
      var index : Nat = 0;
      let launchpad : Launchpad.Property = await LaunchpadUtil.getLaunchpadDetail(launchpadDetail);
      let tokenAdapter = TokenFactory.getAdapter(launchpad.soldTokenId, launchpad.soldTokenStandard);
      let pricingTokenAdapter = TokenFactory.getAdapter(launchpad.pricingTokenId, launchpad.pricingTokenStandard);
      if (tokenMetadata.name == "") {
        try {
          let tokenMeta = await tokenAdapter.metadata();
          tokenMetadata.name := getName(tokenMeta);
        } catch (e) {
          throw Error.reject("get token metadata failed: " #debug_show (Error.message(e)));
        };
      };
      if (pricingTokenMetadata.name == "") {
        try {
          let pricingTokenMeta = await pricingTokenAdapter.metadata();
          pricingTokenMetadata.name := getName(pricingTokenMeta);
          pricingTokenMetadata.symbol := getSymbol(pricingTokenMeta);
          pricingTokenMetadata.decimals := getDecimals(pricingTokenMeta);
        } catch (e) {
          throw Error.reject("get pricingToken metadata failed: " #debug_show (Error.message(e)));
        };
      };
      var totalPricingTokenQuantity : Nat = 0; 
      var totalTokenQuantity : Nat = 0; 
      var tokenTransFee : Nat = 0;
      var pricingTokenTransFee : Nat = 0;
      try {
        var tokenTransFee : Nat = await tokenAdapter.fee();
      } catch (e) {
        throw Error.reject("get_token_fee " # debug_show (Error.message(e)));
      };
      try {
        var pricingTokenTransFee : Nat = await pricingTokenAdapter.fee();
      } catch (e) {
        throw Error.reject("get_pricingToken_fee " # debug_show (Error.message(e)));
      };

      if (investors.size() > 0) {
        let eachTokenTransFee : Nat = Nat.div(tokenTransFee, investors.size());
        let eachPricingTokenTransFee : Nat = Nat.div(pricingTokenTransFee, investors.size());
        for (investor in investors.vals()) {
          let expectedDepositedPricingTokenQuantity : Nat = TextUtil.toNat(investor.expectedDepositedPricingTokenQuantity);
          var pricingTokenQuantity : Nat = expectedDepositedPricingTokenQuantity;
          if (fundraisingTotalTokenQuantity > expectedSellQuantity) {
            pricingTokenQuantity := Nat.div(Nat.mul(expectedDepositedPricingTokenQuantity, expectedSellQuantity), fundraisingTotalTokenQuantity);
          };
          totalPricingTokenQuantity += pricingTokenQuantity;
          var restPricingTokenQuantity : Nat = expectedDepositedPricingTokenQuantity - pricingTokenQuantity;
          if (restPricingTokenQuantity > eachPricingTokenTransFee) {
            restPricingTokenQuantity := restPricingTokenQuantity;
          } else {
            restPricingTokenQuantity := 0;
          };

          var finalTokenQuantity : Nat = await LaunchpadUtil.getTokenQuantityByPricingTokenQuantity(pricingTokenQuantity, TextUtil.toNat(launchpad.initialExchangeRatio), launchpad.soldTokenId, launchpad.soldTokenStandard, launchpad.pricingTokenId, launchpad.pricingTokenStandard);
          if (finalTokenQuantity > eachTokenTransFee) {
            finalTokenQuantity := finalTokenQuantity; // - eachTokenTransFee;
            totalTokenQuantity += finalTokenQuantity;
          } else {
            finalTokenQuantity := 0;
          };

          investors.put(
            index,
            {
              id = investor.id;
              principal = investor.principal;
              participatedDateTime = investor.participatedDateTime;
              expectedDepositedPricingTokenQuantity = investor.expectedDepositedPricingTokenQuantity;
              expectedBuyTokenQuantity = investor.expectedBuyTokenQuantity;
              finalTokenSet = ?{
                token = {
                  name = tokenMetadata.name;
                  symbol = tokenMetadata.symbol;
                  logo = "";
                  quantity = TextUtil.fromNat(finalTokenQuantity);
                };
                pricingToken = {
                  name = pricingTokenMetadata.name;
                  symbol = pricingTokenMetadata.symbol;
                  logo = "";
                  quantity = TextUtil.fromNat(restPricingTokenQuantity);
                };
              };
              withdrawalDateTime = null;
            },
          );
          index += 1;
        };
        return {
          pricingToken = {
            info = {
              name = pricingTokenMetadata.name;
              symbol = pricingTokenMetadata.symbol;
              logo = "";
              quantity = TextUtil.fromNat(totalPricingTokenQuantity);
            };
            transFee = pricingTokenTransFee;
            // view = pricingTokenMetadata;
          };
          token = {
            info = {
              name = tokenMetadata.name;
              symbol = tokenMetadata.symbol;
              logo = "";
              quantity = TextUtil.fromNat(totalTokenQuantity);
            };
            transFee = tokenTransFee;
            // view = tokenMetadata;
          };
        };
      };
      return {
        token = {
          info = {
            name = tokenMetadata.name;
            symbol = tokenMetadata.symbol;
            logo = "";
            quantity = "0";
          };
          // view = tokenMetadata;
          transFee = tokenTransFee;
        };
        pricingToken = {
          info = {
            name = pricingTokenMetadata.name;
            symbol = pricingTokenMetadata.symbol;
            logo = "";
            quantity = "0";
          };
          transFee = pricingTokenTransFee;
          // view = pricingTokenMetadata;
        };
      };
    } else {
      throw Error.reject("Denied!!");
    };
  };

  public shared func uninstall() : async CommonModel.BoolResult {
    installed := false;
    launchpadDetail := null;
    // pricingTokenCanister := null;
    // soldTokenCanister := null;
    investors.clear();
    #ok(not installed);
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
    investorArry := investors.toArray();
    investorAddressArry := investorAddresses.toArray();
  };

  system func postupgrade() {
    for (item in investorArry.vals()) {
      investors.add(item);
    };
    investorArry := [];
    for (item in investorAddressArry.vals()) {
      investorAddresses.add(item);
    };
    investorAddressArry := [];
  };
};
