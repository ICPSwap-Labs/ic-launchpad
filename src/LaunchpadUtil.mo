import Text "mo:base/Text";
import Nat "mo:base/Nat";
import Nat64 "mo:base/Nat64";
import Time "mo:base/Time";
import Error "mo:base/Error";
import Debug "mo:base/Debug";
import Principal "mo:base/Principal";
import CommonModel "mo:commons/model/CommonModel";
import PrincipalUtil "mo:commons/utils/PrincipalUtils";
import TokenFactory "./token/TokenFactory";
import Launchpad "./Launchpad";

module {

  public let DECIMALS : Nat = 18;

  public let CANISTER_NUMBER : Nat = 5;

  public let WALLET_CANISTER_ID = "yudqc-5aaaa-aaaak-aacrq-cai";

  public let ADMIN_LIST : [Text] = ["fbe00b464da19fc7bf234cf05e376631ad896163558174c375f6e9be96d95e95"];

  public let defaultTokenInfo : Launchpad.TokenInfo = {
    name = "";
    symbol = "";
    logo = "";
    transFee = 0;
    quantity = "";
  };

  public let defaultTokenSet : Launchpad.TokenSet = {
    token = defaultTokenInfo;
    pricingToken = defaultTokenInfo;
  };

  public func getValue<T>(r : CommonModel.ResponseResult<T>, default : T) : T {
    switch (r) {
      case (#ok(value)) {
        return value;
      };
      case (#err(code)) {
        return default;
      };
    };
  };

  public func getLaunchpadDetail(prop : ?Launchpad.Property) : async Launchpad.Property {
    return switch (prop) {
      case (?prop) {
        return prop;
      };
      case (_) {
        throw Error.reject("The launchpad property is null.");
      };
    };
  };

  public func getCanisterAddress(canister : actor {}) : Text {
    return PrincipalUtil.toAddress(getCanisterPrincipal(canister));
  };

  public func getCanisterPrincipal(canister : actor {}) : Principal {
    return Principal.fromActor(canister);
  };

  public func getTokenDecimal(tokenId : Text, tokenStandard : Text) : async Nat {
    let tokenAdapter = TokenFactory.getAdapter(tokenId, tokenStandard);

    try {
      var tokenDecimals = 0;
      var tokenMetadata = await tokenAdapter.metadata();
      for ((key, value) in tokenMetadata.vals()) {
        if (key == "decimals") {
          tokenDecimals := switch (value) {
            case (#Nat(decimals)) {
              decimals;
            };
            case (_) {
              0;
            };
          };
        };
      };
      return tokenDecimals;
    } catch (e) {
      throw Error.reject("metadata failed: " # debug_show (Error.message(e)));
    };
  };

  // ratio = token / pricingToken
  public func getPricingTokenQuantityByTokenQuantity(tokenQuantity : Nat, exchangeRatio : Nat, tokenCanisterId : Text, tokenStandard : Text, pricingTokenCanisterId : Text, pricingTokenStandard : Text) : async Nat {
    let tokenDecimal : Nat = await getTokenDecimal(tokenCanisterId, tokenStandard);
    let pricingTokenDecimal : Nat = await getTokenDecimal(pricingTokenCanisterId, pricingTokenStandard);
    return Nat.div(Nat.mul(Nat.mul(tokenQuantity, exchangeRatio), Nat.pow(10, pricingTokenDecimal)), Nat.mul(Nat.pow(10, DECIMALS), Nat.pow(10, tokenDecimal)));
  };

  public func getTokenQuantityByPricingTokenQuantity(pricingTokenQuantity : Nat, exchangeRatio : Nat, tokenCanisterId : Text, tokenStandard : Text, pricingTokenCanisterId : Text, pricingTokenStandard : Text) : async Nat {
    let tokenDecimal : Nat = await getTokenDecimal(tokenCanisterId, tokenStandard);
    let pricingTokenDecimal : Nat = await getTokenDecimal(pricingTokenCanisterId, pricingTokenStandard);
    return Nat.div(Nat.mul(Nat.mul(pricingTokenQuantity, Nat.pow(10, DECIMALS)), Nat.pow(10, tokenDecimal)), Nat.mul(exchangeRatio, Nat.pow(10, pricingTokenDecimal)));
  };

  public func convertDecimals(tokenQuantity : Nat, tokenDecimal : Nat) : Nat {
    return Nat.div(Nat.mul(tokenQuantity, Nat.pow(10, DECIMALS)), Nat.pow(10, tokenDecimal));
  };

  public func getBalance(principal : Principal, tokenCid : Text, tokenStandard : Text) : async Nat {
    let tokenAdapter = TokenFactory.getAdapter(tokenCid, tokenStandard);
    try {
      let tokenBalance : Nat = await tokenAdapter.balanceOf(
        {
          owner = principal;
          subaccount = null;
        }
      );
      return tokenBalance;
    } catch (e) {
      throw Error.reject("insufficient_token_balance " # debug_show (Error.message(e)));
    };
  };

  public func getFee(tokenCid : Text, tokenStandard : Text) : async Nat {
    let tokenAdapter = TokenFactory.getAdapter(tokenCid, tokenStandard);
    try {
      var tokenFee : Nat = await tokenAdapter.fee();
      return tokenFee;
    } catch (e) {
      throw Error.reject("get_token_fee " # debug_show (Error.message(e)));
    };
  };

  public func getExtraQuntity(tokenCid : Text, tokenStandard : Text) : async Nat {
    let tokenAdapter = TokenFactory.getAdapter(tokenCid, tokenStandard);
    let fee : Nat = await getFee(tokenCid, tokenStandard);
    return Nat.mul(Nat.mul(fee, 5), 10);
  };
};
