import Text "mo:base/Text";
import Nat "mo:base/Nat";
import Int "mo:base/Int";
import Time "mo:base/Time";
import Bool "mo:base/Bool";
import Principal "mo:base/Principal";
import CommonModel "mo:commons/model/CommonModel";

module {

    public type Property = {
        id : Text;
        cid : Text;
        name : Text;
        description : Text;
        startDateTime : Time.Time;
        endDateTime : Time.Time;
        depositDateTime : ?Time.Time;
        withdrawalDateTime : ?Time.Time;
        soldTokenId : Text;
        soldTokenStandard : Text;
        pricingTokenId : Text;
        pricingTokenStandard : Text;
        initialExchangeRatio : Text;
        soldQuantity : Text;
        expectedSellQuantity : Text;
        extraTokenFee : ?Nat;
        depositedQuantity : Text;
        fundraisingPricingTokenQuantity : ?Text;
        expectedFundraisingPricingTokenQuantity : Text;
        limitedAmountOnce : Text;
        receiveTokenDateTime : Time.Time;
        creator : Text;
        creatorPrincipal : Principal;
        createdDateTime : Time.Time;
        settled : ?Bool;
        canisterQuantity : Nat;
    };

    public type Investor = {
        id : Text;
        principal : Principal;
        participatedDateTime : Time.Time;
        expectedBuyTokenQuantity : Text;
        expectedDepositedPricingTokenQuantity : Text;
        finalTokenSet : ?TokenSet;
        withdrawalDateTime : ?Time.Time;
    };

    public type InvestorUnit = {
        investor : Investor;
        index : Int;
    };

    public type TokenSet = {
        token : TokenInfo;
        pricingToken : TokenInfo;
    };

    public type TokenViewSet = {
        token : {
            info : TokenInfo;
            transFee : Nat;
        };
        pricingToken : {
            info : TokenInfo;
            transFee : Nat;
        };
    };

    public type TokenInfo = {
        name : Text;
        symbol : Text;
        logo : Text;
        quantity : Text;
    };

    public type TicketPackage = {
        ticket : Text;
        cid : Text;
    };

    public type HistoryTransaction = {
        managerAddress : Text;
        launchpadAddress : Text;
        time : Time.Time;
        operationType : Text;
        tokenName : Text;
        tokenSymbol : Text;
        quantity : Text;
        address : Text;
    };

    public type LaunchpadCanister = actor {
        //1. transfer pricing token from investor account to canister with subaccount
        //2. transfer pricing token from canister subaccount to canister
        addInvestor : shared () -> async CommonModel.BoolResult;
        //1. approve pricing token from investor account to canister
        //2. transferFrom pricing token from investor account to canister
        addInvestorFromApprove : shared (Text) -> async CommonModel.BoolResult;
        //1. transfer pricing token from investor account to canister with subaccount
        //2. transfer pricing token from canister subaccount to canister
        appendPricingTokenQuantity : shared () -> async CommonModel.BoolResult;
        //1. approve pricing token from investor account to canister
        //2. transferFrom pricing token from investor account to canister
        appendPricingTokenQuantityFromApprove : shared (Text) -> async CommonModel.BoolResult;

        install : shared (Property, Text, [Text]) -> async CommonModel.BoolResult;
        addInvestorAddress : shared (Text) -> async ();
        getInvestorsSize : query () -> async Nat;
        getInvestors : query () -> async [Investor];
        withdraw2Investor : shared () -> async CommonModel.ResponseResult<TokenSet>;
        getInvestorDetail : query (Text) -> async CommonModel.ResponseResult<Investor>;
        getPricingTokenQuantity : query () -> async CommonModel.ResponseResult<Nat>;
        computeFinalTokenViewSet : shared (Nat, Nat) -> async TokenViewSet;
        transferByAddress : shared (Principal, Principal, Nat, Text, Text) -> async Bool;
        uninstall : shared () -> async CommonModel.BoolResult;
    };

    public type LaunchpadManager = actor {
        install : shared (Principal, Property, [Text]) -> async CommonModel.ResponseResult<Property>;
        getDetail : query () -> async CommonModel.ResponseResult<Property>;
        getWhitelistSize : query () -> async Nat;
        inWhitelist : query (Text) -> async CommonModel.BoolResult;
        getWhitelist : query (Nat, Nat) -> async CommonModel.ResponseResult<CommonModel.Page<Text>>;
        withdraw : shared () -> async CommonModel.ResponseResult<TokenSet>;
        generateTicket : shared (Text) -> async CommonModel.ResponseResult<Text>;
        getTicketPackage : query (Text, Text) -> async CommonModel.ResponseResult<TicketPackage>;
        getPricingTokenQuantity : shared () -> async CommonModel.ResponseResult<Text>;
        getInvestorsSize : shared () -> async CommonModel.ResponseResult<Nat>;
        getLaunchpadCanisters : query () -> async [LaunchpadCanister];
        settle : shared () -> async CommonModel.BoolResult;
        archive : shared () -> async ();
        uninstall : shared () -> async CommonModel.BoolResult;
    };
};
