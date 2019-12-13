pragma solidity ^0.5.13;

library FixidityLib {

    uint8 constant public initial_digits = 36;
    int256 constant public fixed_e =            2718281828459045235360287471352662498;
    int256 constant public fixed_pi =           3141592653589793238462643383279502884;
    int256 constant public fixed_exp_10 =   22026465794806716516957900645284244000000;

	struct Fixidity {
		uint8 digits;
		int256 fixed_1;
		int256 fixed_e;
        int256 fixed_pi;
        int256 fixed_exp_10;
	}

    function init(Fixidity storage fixidity, uint8 digits) public {
        assert(digits < 36);
        fixidity.digits = digits;
        fixidity.fixed_1 = int256(uint256(10) ** uint256(digits));
        int256 t = int256(uint256(10) ** uint256(initial_digits - digits));
        fixidity.fixed_e = fixed_e / t;
        fixidity.fixed_pi = fixed_pi / t;
        fixidity.fixed_exp_10 = fixed_exp_10 / t;
    }

    function round(Fixidity storage fixidity, int256 v) public view returns (int256) {
        return round_off(fixidity, v, fixidity.digits);
    }

    function floor(Fixidity storage fixidity, int256 v) public view returns (int256) {
        return (v / fixidity.fixed_1) * fixidity.fixed_1;
    }

    function multiply(Fixidity storage fixidity, int256 a, int256 b) public view returns (int256) {
        if(b == fixidity.fixed_1) return a;
        int256 x1 = a / fixidity.fixed_1;
        int256 x2 = a - fixidity.fixed_1 * x1;
        int256 y1 = b / fixidity.fixed_1;
        int256 y2 = b - fixidity.fixed_1 * y1;
        return fixidity.fixed_1 * x1 * y1 + x1 * y2 + x2 * y1 + x2 * y2 / fixidity.fixed_1;
    }

    function divide(Fixidity storage fixidity, int256 a, int256 b) public view returns (int256) {
        if(b == fixidity.fixed_1) return a;
        assert(b != 0);
        return multiply(fixidity, a, reciprocal(fixidity, b));
    }

    function add(Fixidity storage fixidity, int256 a, int256 b) public view returns (int256) {
    	int256 t = a + b;
        assert(t - a == b);
    	return t;
    }

    function subtract(Fixidity storage fixidity, int256 a, int256 b) public view returns (int256) {
    	int256 t = a - b;
    	assert(t + b == a);
    	return t;
    }

    function reciprocal(Fixidity storage fixidity, int256 a) public view returns (int256) {
        return round_off(fixidity, 10 * fixidity.fixed_1 * fixidity.fixed_1 / a, 1) / 10;
    }

    function round_off(Fixidity storage fixidity, int256 v, uint8 digits) public view returns (int256) {
        int256 t = int256(uint256(10) ** uint256(digits));
        int8 sign = 1;
        if(v < 0) {
            sign = -1;
            v = 0 - v;
        }
        if(v % t >= t / 2) v = v + t - v % t;
        return v * sign;
    }

    function round_to(Fixidity storage fixidity, int256 v, uint8 digits) public view returns (int256) {
        assert(digits < fixidity.digits);
        return round_off(fixidity, v, fixidity.digits - digits);
    }

    function trunc_digits(Fixidity storage fixidity, int256 v, uint8 digits) public view returns (int256) {
        if(digits <= 0) return v;
        return round_off(fixidity, v, digits) / (10 ** digits);
    }
    
    uint8 constant public longer_digits = 36;
    int256 constant public longer_fixed_log_e_1_5 =     405465108108164381978013115464349137;//ln(1.5)
    int256 constant public longer_fixed_1 =            1000000000000000000000000000000000000;
    int256 constant public longer_fixed_log_e_10 =     2302585092994045684017991454684364208;//ln(10)

    function log_e(FixidityLib.Fixidity storage fixidity, int256 v) public view returns (int256) {
        assert(v > 0);
        int256 r = 0;
        uint8 extra_digits = longer_digits - fixidity.digits;
        int256 t = int256(uint256(10) ** uint256(extra_digits));
        while(v <= fixidity.fixed_1 / 10) {
            v = v * 10;
            r -= longer_fixed_log_e_10;
        }
        while(v >= 10 * fixidity.fixed_1) {
            v = v / 10;
            r += longer_fixed_log_e_10;
        }
        while(v < fixidity.fixed_1) {
            v = multiply(fixidity, v, fixed_e);
            r -= longer_fixed_1;
        }
        while(v > fixidity.fixed_e) {
            v = divide(fixidity, v, fixed_e);
            r += longer_fixed_1;
        }
        if(v == fixidity.fixed_1) {
            return round_off(fixidity, r, extra_digits) / t;
        }
        if(v == fixidity.fixed_e) {
            return fixidity.fixed_1 + round_off(fixidity, r, extra_digits) / t;
        }
        v *= t;
        v = v - 3 * longer_fixed_1 / 2;
        r = r + longer_fixed_log_e_1_5;
        int256 m = longer_fixed_1 * v / (v + 3 * longer_fixed_1);
        r = r + 2 * m;
        int256 m_2 = m * m / longer_fixed_1;
        uint8 i = 3;
        while(true) {
            m = m * m_2 / longer_fixed_1;
            r = r + 2 * m / int256(i);
            i += 2;
            if(i >= 3 + 2 * fixidity.digits) break;
        }
        return round_off(fixidity, r, extra_digits) / t;
    }

    function log_any(FixidityLib.Fixidity storage fixidity, int256 base, int256 v) public view returns (int256) {
        return divide(fixidity, log_e(fixidity, v), log_e(fixidity, base));
    }
    function power_e(FixidityLib.Fixidity storage fixidity, int256 x) public view returns (int256) {
        assert(x < 172 * fixidity.fixed_1);
    	int256 r = fixidity.fixed_1;
        while(x >= 10 * fixidity.fixed_1) {
            x -= 10 * fixidity.fixed_1;
            r = multiply(fixidity, r, fixidity.fixed_exp_10);
        }
        if(x == fixidity.fixed_1) {
            return multiply(fixidity, r, fixidity.fixed_e);
        } else if(x == 0) {
            return r;
        }
        int256 tr = 100 * fixidity.fixed_1;
        int256 d = tr;
        for(uint8 i = 1; i <= 2 * fixidity.digits; i++) {
            d = (d * x) / (fixidity.fixed_1 * i);
            tr += d;
        }
    	return trunc_digits(fixidity, multiply(fixidity, tr, r), 2);
    }

    function power_any(FixidityLib.Fixidity storage fixidity, int256 a, int256 b) public view returns (int256) {
        return power_e(fixidity, multiply(fixidity, log_e(fixidity, a), b));
    }

    function root_any(FixidityLib.Fixidity storage fixidity, int256 a, int256 b) public view returns (int256) {
        return power_any(fixidity, a, reciprocal(fixidity, b));
    }

    function root_n(FixidityLib.Fixidity storage fixidity, int256 a, uint8 n) public view returns (int256) {
        return power_e(fixidity, divide(fixidity, log_e(fixidity, a), fixidity.fixed_1 * n));
    }
}