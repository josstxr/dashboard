<?php

namespace App\Imports;

use App\Models\Food;
use Maatwebsite\Excel\Concerns\ToModel;
use Maatwebsite\Excel\Concerns\WithHeadingRow;

class FoodsImport implements ToModel, WithHeadingRow
{
    public function model(array $row)
    {
        return new Food([
            'name'     => $row['nombre'],
            'calories' => $row['calorias'],
            'protein'  => $row['proteina'],
            'carbs'    => $row['carbohidratos'],
            'fats'     => $row['grasas'],
        ]);
    }
}