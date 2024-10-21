![king_of_liquidity](https://github.com/user-attachments/assets/270e4702-cb1a-4b7d-8791-fad3844bc923)

### Hook title:

**King Of Liquidity**

### Hook description:

The King Of Liquidity Hook is an ingenious smart contract hooked to Balancer Version 3. This hook tracks and rewards the top liquidity provider of the pool, enhancing user engagement, incentivizing healthy competition, and incentivizing time-weighted liquidity which is beneficial to the pool users.

Demo video: https://youtu.be/ZpzxAV82s0E
Github repo: https://github.com/utuku999/balancer-hookathon

### Team Name:

Utuku

### Features:

The contract operates autonomously and transparently, without relying on external oracles, while maintaining simplicity. It calculates points using a time-weighted average rather than solely basing them on the amount. Rewards are collected from fees and distributed periodically in epochs, supporting various pool tokens. The percentage of fees is configurable.

_Key advantages include fostering user engagement, promoting competition, and gamifying the liquidity provision. Top LPs are rewarded extra for their risk and contribution to the pools over an extended period._

### Pool Lifecycle Implementation Points:

- _onRegister_: check if the factory is allowed and the pool is deployed by an allowed factory.
- _onAfterAddLiquidity_: check if the epoch has ended (if so then reward and start a new one), and update the user’s score. Determine the current king.
- _onAfterRemoveLiquidity_: same as onAfterAddLiquidity but decreases user’s score for pulling out liquidity.
- _onAfterSwap_: check if the epoch has ended (if so then reward and start a new one), and collect an extra percentage of the fee for rewards.

### Identified challenges:

- Liquidity provision is the most beneficial when combining the amount with time. There is little value if the user provides a large amount of LP over just 1 block. Thus we decided that users' scores should consist of time-weighted points.
- If you are not early, you might find it difficult to compete against the OGs. Thus we decided to split time slots into a reasonable duration epoch (e.g. 1 week), after which scores reset and a new king will be determined.
- Users can send / trade their LP tokens between accounts. Tackling this challenge is beyond the current scope because there is no way to hook up ERC20 transfers.
- Collected swap fees (tokens) should have enough value to send or swap them. If the values are too large, an unexpected slippage might occur.
- Users may try to gamify and exploit the system, so it should be secure and laid out thoroughly.
- Configure reasonable epoch duration, extra fee, and other parameters by the admin.

### Future improvements (potential):

- Distribute rewards among multiple top liquidity providers, with configurable allocation methods (equal split or custom criteria).
- Optionally, distribute rewards proportionally based on the duration of each user's reign as King, rather than awarding solely to the final monarch.
- Optionally (batch) convert all accrued fee tokens to BAL or veBAL before distribution, promoting increased usage of governance tokens.
- Maintain a historical record of winners by epoch for future reference. Mint a unique NFT for the reigning King, in addition to distributing rewards.
- Enhance the point calculation mechanism to incorporate factors beyond the time-weighted average.
- Allow admins to set customizable epoch durations and other parameters.
- Implement a function enabling external users to initiate reward distribution once an epoch concludes.
- Track and report the cumulative amount of rewards distributed by the hook contract.
- Establish a blacklist of addresses to exclude from consideration (e.g., team adding initial liquidity).

### Feedback about DevX:

Balancer offers a mainly positive developer experience (DevX), providing thorough and comprehensive resources for swift onboarding to their platform. The community and social channels are active and notably supportive, which further enhances the learning process and progress. While some concepts initially seem challenging and difficult to comprehend, they become trivial with enough determination, time, and practice. The scaffold, along with various projects and examples, is invaluable for developers who are starting with the Balancer ecosystem, significantly easing their integration and learning curve. All in all, it was a pleasure to get hands-on experience with V3 hooks and the Balancer ecosystem.
