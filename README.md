# This is going to be cross-chain Rebase Token

1. A protocol that allows user to deposit into a vault and in return, reciever rebase tokens that represent their underlying balance.

2. Creating a rebase token -> balanceOf function is dynamic to show the changing balance with time.
        - Balance increases linealy with time
        - mint tokens to our users every time they perform an action (minting, burning, transfering, or...bridging) view function
        
3. Interest rate 
        - Individually set an interest rate or each user based on some global interest rate of the protocol at the time the user deposits into the vault.
        - This global interest rates can only decrease to incentivised/reward early adopters.
        - Increase token adoption!